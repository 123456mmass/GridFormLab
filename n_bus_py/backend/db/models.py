"""SQLAlchemy ORM models."""

from __future__ import annotations

import datetime

from sqlalchemy import Boolean, DateTime, Float, ForeignKey, Integer, String, Text
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship


class Base(DeclarativeBase):
    pass


class User(Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    username: Mapped[str] = mapped_column(String(100), unique=True, nullable=False, index=True)
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    created_at: Mapped[datetime.datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.datetime.now(datetime.timezone.utc)
    )

    personas: Mapped[list["UserPersona"]] = relationship(back_populates="user", cascade="all, delete-orphan")
    conversations: Mapped[list["Conversation"]] = relationship(back_populates="user", cascade="all, delete-orphan")


class UserPersona(Base):
    __tablename__ = "user_personas"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[str] = mapped_column(String(36), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    ai_tone: Mapped[str | None] = mapped_column(String(50))
    ai_style: Mapped[str | None] = mapped_column(String(50))
    language_preference: Mapped[str | None] = mapped_column(String(10))
    custom_prompt: Mapped[str | None] = mapped_column(Text)
    is_default: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime.datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.datetime.now(datetime.timezone.utc)
    )
    updated_at: Mapped[datetime.datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.datetime.now(datetime.timezone.utc),
        onupdate=datetime.datetime.now(datetime.timezone.utc)
    )

    user: Mapped["User"] = relationship(back_populates="personas")


class Case(Base):
    __tablename__ = "cases"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(200), unique=True, nullable=False, index=True)
    system_name: Mapped[str | None] = mapped_column(String(500))
    bus_count: Mapped[int | None] = mapped_column(Integer)
    line_count: Mapped[int | None] = mapped_column(Integer)
    data: Mapped[dict] = mapped_column(JSONB, nullable=False)
    created_at: Mapped[datetime.datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.datetime.now(datetime.timezone.utc)
    )

    runs: Mapped[list["RunHistory"]] = relationship(back_populates="case", cascade="all, delete-orphan")


class RunHistory(Base):
    __tablename__ = "run_history"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    case_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("cases.id", ondelete="SET NULL"))
    solver: Mapped[str] = mapped_column(String(50), nullable=False, index=True)
    options: Mapped[dict | None] = mapped_column(JSONB)
    converged: Mapped[bool | None] = mapped_column(Boolean)
    iterations: Mapped[int | None] = mapped_column(Integer)
    tolerance: Mapped[float | None] = mapped_column(Float)
    P_loss: Mapped[float | None] = mapped_column(Float)
    Q_loss: Mapped[float | None] = mapped_column(Float)
    execution_time_ms: Mapped[float | None] = mapped_column(Float)
    result_data: Mapped[dict | None] = mapped_column(JSONB)
    started_at: Mapped[datetime.datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.datetime.now(datetime.timezone.utc)
    )

    case: Mapped[Case | None] = relationship(back_populates="runs")


class Conversation(Base):
    __tablename__ = "conversations"

    id: Mapped[str] = mapped_column(String(12), primary_key=True)
    user_id: Mapped[str | None] = mapped_column(String(36), ForeignKey("users.id", ondelete="CASCADE"), index=True)
    session_type: Mapped[str] = mapped_column(String(20), default="chat")
    title: Mapped[str | None] = mapped_column(String(300))
    persona_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("user_personas.id", ondelete="SET NULL"))
    analysis_context: Mapped[dict | None] = mapped_column(JSONB)
    messages: Mapped[list] = mapped_column(JSONB, nullable=False, default=list)
    created_at: Mapped[datetime.datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.datetime.now(datetime.timezone.utc)
    )
    last_access: Mapped[datetime.datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.datetime.now(datetime.timezone.utc)
    )

    user: Mapped["User | None"] = relationship(back_populates="conversations")


class SavedConfig(Base):
    __tablename__ = "saved_configs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str | None] = mapped_column(String(200))
    solver_type: Mapped[str | None] = mapped_column(String(50))
    config: Mapped[dict] = mapped_column(JSONB, nullable=False)
    created_at: Mapped[datetime.datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.datetime.now(datetime.timezone.utc)
    )
