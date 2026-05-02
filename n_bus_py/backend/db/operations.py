"""Async DB operations for saving/querying run history, conversations, users, and personas."""

from __future__ import annotations

import datetime

from sqlalchemy import select, update, delete
from sqlalchemy.ext.asyncio import AsyncSession

from .database import async_session_factory
from .models import Conversation, RunHistory, User, UserPersona


# ── Run History ────────────────────────────────────────────

async def save_run(
    case_name: str,
    solver: str,
    options: dict | None,
    converged: bool,
    iterations: int,
    P_loss: float | None,
    Q_loss: float | None,
    execution_time_ms: float | None,
    result_data: dict | None = None,
):
    async with async_session_factory() as session:
        run = RunHistory(
            solver=solver,
            options=options,
            converged=converged,
            iterations=iterations,
            P_loss=P_loss,
            Q_loss=Q_loss,
            execution_time_ms=execution_time_ms,
            result_data=result_data,
        )
        session.add(run)
        await session.commit()


async def get_recent_runs(limit: int = 50, solver: str | None = None) -> list[dict]:
    async with async_session_factory() as session:
        q = select(RunHistory).order_by(RunHistory.started_at.desc()).limit(limit)
        if solver:
            q = q.where(RunHistory.solver == solver)
        result = await session.execute(q)
        rows = result.scalars().all()
        return [
            {
                "id": r.id,
                "solver": r.solver,
                "converged": r.converged,
                "iterations": r.iterations,
                "P_loss": r.P_loss,
                "Q_loss": r.Q_loss,
                "execution_time_ms": r.execution_time_ms,
                "started_at": r.started_at.isoformat() if r.started_at else None,
            }
            for r in rows
        ]


# ── Users ──────────────────────────────────────────────────

async def create_user(user_id: str, username: str, password_hash: str) -> str:
    async with async_session_factory() as session:
        user = User(id=user_id, username=username, password_hash=password_hash)
        session.add(user)
        await session.commit()
        return user.id


async def get_user_by_username(username: str) -> User | None:
    async with async_session_factory() as session:
        result = await session.execute(select(User).where(User.username == username))
        return result.scalar_one_or_none()


async def get_user_by_id(user_id: str) -> User | None:
    async with async_session_factory() as session:
        result = await session.execute(select(User).where(User.id == user_id))
        return result.scalar_one_or_none()


# ── Personas ───────────────────────────────────────────────

async def create_persona(user_id: str, data: dict) -> dict:
    async with async_session_factory() as session:
        # unset existing default if this one is default
        if data.get("is_default"):
            await session.execute(
                update(UserPersona)
                .where(UserPersona.user_id == user_id)
                .values(is_default=False)
            )
        persona = UserPersona(user_id=user_id, **data)
        session.add(persona)
        await session.commit()
        await session.refresh(persona)
        return _persona_to_dict(persona)


async def update_persona(persona_id: int, user_id: str, data: dict) -> bool:
    async with async_session_factory() as session:
        if data.get("is_default"):
            await session.execute(
                update(UserPersona)
                .where(UserPersona.user_id == user_id)
                .values(is_default=False)
            )
        result = await session.execute(
            update(UserPersona)
            .where(UserPersona.id == persona_id, UserPersona.user_id == user_id)
            .values(**data, updated_at=datetime.datetime.now(datetime.timezone.utc))
        )
        await session.commit()
        return result.rowcount > 0


async def delete_persona(persona_id: int, user_id: str) -> bool:
    async with async_session_factory() as session:
        result = await session.execute(
            delete(UserPersona).where(
                UserPersona.id == persona_id, UserPersona.user_id == user_id
            )
        )
        await session.commit()
        return result.rowcount > 0


async def get_personas(user_id: str) -> list[dict]:
    async with async_session_factory() as session:
        result = await session.execute(
            select(UserPersona)
            .where(UserPersona.user_id == user_id)
            .order_by(UserPersona.is_default.desc(), UserPersona.created_at.asc())
        )
        return [_persona_to_dict(r) for r in result.scalars().all()]


async def get_default_persona(user_id: str) -> dict | None:
    async with async_session_factory() as session:
        result = await session.execute(
            select(UserPersona).where(
                UserPersona.user_id == user_id, UserPersona.is_default == True
            )
        )
        p = result.scalar_one_or_none()
        return _persona_to_dict(p) if p else None


async def get_persona_by_id(persona_id: int, user_id: str) -> dict | None:
    async with async_session_factory() as session:
        result = await session.execute(
            select(UserPersona).where(
                UserPersona.id == persona_id, UserPersona.user_id == user_id
            )
        )
        p = result.scalar_one_or_none()
        return _persona_to_dict(p) if p else None


def _persona_to_dict(p: UserPersona) -> dict:
    return {
        "id": p.id,
        "user_id": p.user_id,
        "name": p.name,
        "ai_tone": p.ai_tone,
        "ai_style": p.ai_style,
        "language_preference": p.language_preference,
        "custom_prompt": p.custom_prompt,
        "is_default": p.is_default,
        "created_at": p.created_at.isoformat() if p.created_at else None,
        "updated_at": p.updated_at.isoformat() if p.updated_at else None,
    }


# ── Conversations ──────────────────────────────────────────

async def save_conversation(
    conv_id: str,
    user_id: str | None = None,
    session_type: str = "chat",
    messages: list[dict] | None = None,
    title: str | None = None,
    persona_id: int | None = None,
    analysis_context: dict | None = None,
):
    async with async_session_factory() as session:
        conv = Conversation(
            id=conv_id,
            user_id=user_id,
            session_type=session_type,
            messages=messages or [],
            title=title,
            persona_id=persona_id,
            analysis_context=analysis_context,
            last_access=datetime.datetime.now(datetime.timezone.utc),
        )
        await session.merge(conv)
        await session.commit()


async def get_conversation(conv_id: str) -> list[dict] | None:
    async with async_session_factory() as session:
        result = await session.execute(
            select(Conversation).where(Conversation.id == conv_id)
        )
        conv = result.scalar_one_or_none()
        if conv is None:
            return None
        conv.last_access = datetime.datetime.now(datetime.timezone.utc)
        await session.commit()
        return conv.messages


async def get_conversation_full(conv_id: str) -> dict | None:
    """Return full conversation record as dict."""
    async with async_session_factory() as session:
        result = await session.execute(
            select(Conversation).where(Conversation.id == conv_id)
        )
        conv = result.scalar_one_or_none()
        if conv is None:
            return None
        conv.last_access = datetime.datetime.now(datetime.timezone.utc)
        await session.commit()
        return {
            "id": conv.id,
            "user_id": conv.user_id,
            "session_type": conv.session_type,
            "title": conv.title,
            "persona_id": conv.persona_id,
            "analysis_context": conv.analysis_context,
            "messages": conv.messages,
            "created_at": conv.created_at.isoformat() if conv.created_at else None,
            "last_access": conv.last_access.isoformat() if conv.last_access else None,
        }


async def list_user_sessions(
    user_id: str, session_type: str | None = None, limit: int = 50
) -> list[dict]:
    async with async_session_factory() as session:
        q = select(Conversation).where(Conversation.user_id == user_id)
        if session_type:
            q = q.where(Conversation.session_type == session_type)
        q = q.order_by(Conversation.last_access.desc()).limit(limit)
        result = await session.execute(q)
        rows = result.scalars().all()
        return [
            {
                "id": r.id,
                "title": r.title,
                "session_type": r.session_type,
                "message_count": len(r.messages) if r.messages else 0,
                "created_at": r.created_at.isoformat() if r.created_at else None,
                "last_access": r.last_access.isoformat() if r.last_access else None,
            }
            for r in rows
        ]


async def delete_session(session_id: str, user_id: str) -> bool:
    async with async_session_factory() as session:
        result = await session.execute(
            delete(Conversation).where(
                Conversation.id == session_id, Conversation.user_id == user_id
            )
        )
        await session.commit()
        return result.rowcount > 0


async def update_session_title(session_id: str, title: str) -> bool:
    async with async_session_factory() as session:
        result = await session.execute(
            update(Conversation)
            .where(Conversation.id == session_id)
            .values(title=title)
        )
        await session.commit()
        return result.rowcount > 0
