"""Edge case tests — zero-impedance, Q-limits, validation, convergence."""

import numpy as np
import pytest

from pfsolver import model, newton_raphson, gauss_seidel, fast_decoupled


# ── Case fixtures ──────────────────────────────────────────

@pytest.fixture(scope="module")
def zero_impedance_case():
    """Two buses connected by zero-impedance line (should be handled)."""
    return {
        "system_name": "Zero-Z Test",
        "base_values": {"S_base_MVA": 100.0, "V_base_kV": 230.0},
        "bus_data": [
            [1, 1, 1.06, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, -999, 999],
            [2, 3, 1.00, 0.0, 0.0, 0.0, 0.4, 0.1, 0.0, 0.0, -999, 999],
        ],
        "line_data": [
            [1, 2, 0.0, 0.001, 0.0, 1.0, 0.0],
        ],
    }


@pytest.fixture(scope="module")
def q_limit_violation_case():
    """PV bus with Q generation exceeding limits."""
    return {
        "system_name": "Q-Limit Test",
        "base_values": {"S_base_MVA": 100.0, "V_base_kV": 230.0},
        "bus_data": [
            [1, 1, 1.06, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, -999, 999],
            [2, 2, 1.00, 0.0, 0.3, 0.0, 0.0, 0.0, 0.0, 0.0, -0.05, 1.0],
            [3, 3, 1.00, 0.0, 0.0, 0.0, 0.5, 0.2, 0.0, 0.0, -999, 999],
        ],
        "line_data": [
            [1, 2, 0.02, 0.06, 0.03, 1.0, 0.0],
            [2, 3, 0.04, 0.12, 0.02, 1.0, 0.0],
        ],
    }


@pytest.fixture(scope="module")
def all_pq_case():
    """System with slack + all PQ buses (no PV)."""
    return {
        "system_name": "All-PQ Test",
        "base_values": {"S_base_MVA": 100.0, "V_base_kV": 230.0},
        "bus_data": [
            [1, 1, 1.06, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, -999, 999],
            [2, 3, 1.00, 0.0, 0.0, 0.0, 0.3, 0.1, 0.0, 0.0, -999, 999],
            [3, 3, 1.00, 0.0, 0.0, 0.0, 0.3, 0.1, 0.0, 0.0, -999, 999],
        ],
        "line_data": [
            [1, 2, 0.02, 0.06, 0.03, 1.0, 0.0],
            [2, 3, 0.04, 0.12, 0.02, 1.0, 0.0],
        ],
    }


@pytest.fixture(scope="module")
def purely_inductive_case():
    """Lines with R=0 (purely inductive)."""
    return {
        "system_name": "Purely Inductive Test",
        "base_values": {"S_base_MVA": 100.0, "V_base_kV": 230.0},
        "bus_data": [
            [1, 1, 1.06, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, -999, 999],
            [2, 3, 1.00, 0.0, 0.0, 0.0, 0.4, 0.1, 0.0, 0.0, -999, 999],
            [3, 3, 1.00, 0.0, 0.0, 0.0, 0.4, 0.1, 0.0, 0.0, -999, 999],
        ],
        "line_data": [
            [1, 2, 0.0, 0.06, 0.03, 1.0, 0.0],
            [2, 3, 0.0, 0.12, 0.02, 1.0, 0.0],
        ],
    }


# ── NR Tests ───────────────────────────────────────────────

class TestNRZeroImpedance:
    @pytest.fixture(scope="class")
    def result(self, zero_impedance_case):
        return newton_raphson.solve(zero_impedance_case)

    def test_handles_near_zero_impedance(self, result):
        assert "error" not in result

    def test_no_nan(self, result):
        assert not np.isnan(result["bus_voltage"]).any()


class TestNRQLimits:
    @pytest.fixture(scope="class")
    def result_enabled(self, q_limit_violation_case):
        return newton_raphson.solve(q_limit_violation_case, {
            "enforce_q_limits": True,
            "tolerance": 1e-6,
        })

    @pytest.fixture(scope="class")
    def result_disabled(self, q_limit_violation_case):
        return newton_raphson.solve(q_limit_violation_case, {
            "enforce_q_limits": False,
            "tolerance": 1e-6,
        })

    def test_both_converge(self, result_enabled, result_disabled):
        assert result_enabled["converged"] is True
        assert result_disabled["converged"] is True

    def test_q_switching_events_present(self, result_enabled):
        assert "q_limit_switching" in result_enabled
        assert result_enabled["q_limit_switching"]["enabled"] is True


class TestNRAllPQ:
    @pytest.fixture(scope="class")
    def result(self, all_pq_case):
        return newton_raphson.solve(all_pq_case)

    def test_converges(self, result):
        assert result["converged"] is True

    def test_voltages_positive(self, result):
        assert np.all(result["bus_voltage"] > 0)


class TestNRPurelyInductive:
    @pytest.fixture(scope="class")
    def result(self, purely_inductive_case):
        return newton_raphson.solve(purely_inductive_case)

    def test_converges(self, result):
        assert result["converged"] is True

    def test_active_power_loss_near_zero(self, result):
        assert abs(result["P_loss_total"]) < 1e-4


# ── GS Tests ───────────────────────────────────────────────

class TestGSAllPQ:
    @pytest.fixture(scope="class")
    def result(self, all_pq_case):
        return gauss_seidel.solve(all_pq_case, {"max_iter": 500, "tolerance": 1e-6})

    def test_runs(self, result):
        assert "error" not in result

    def test_voltage_reasonable(self, result):
        V = result["bus_voltage"]
        assert np.all(V >= 0.90)
        assert np.all(V <= 1.12)


# ── FDLF Tests ─────────────────────────────────────────────

class TestFDLFAllPQ:
    @pytest.fixture(scope="class")
    def result(self, all_pq_case):
        return fast_decoupled.solve(all_pq_case)

    def test_runs(self, result):
        assert "error" not in result


class TestFDLFPurelyInductive:
    @pytest.fixture(scope="class")
    def result(self, purely_inductive_case):
        return fast_decoupled.solve(purely_inductive_case)

    def test_converges(self, result):
        assert result["converged"] is True


# ── Model Tests ─────────────────────────────────────────────

class TestModelEdgeCases:
    def test_prepare_all_pq(self, all_pq_case):
        m = model.prepare_model(all_pq_case)
        assert m.num_buses == 3
        assert len(m.pq_buses) == 2
        assert len(m.pv_buses) == 0

    def test_prepare_zero_impedance(self, zero_impedance_case):
        m = model.prepare_model(zero_impedance_case)
        # Should handle near-zero impedance gracefully
        assert np.isfinite(m.Ybus).all()

    def test_prepare_purely_inductive(self, purely_inductive_case):
        m = model.prepare_model(purely_inductive_case)
        assert m.num_lines == 2


# ── Validation Tests ───────────────────────────────────────

class TestValidation:
    def test_duplicate_bus_ids(self):
        with pytest.raises(ValueError, match="Duplicate"):
            model.prepare_model({
                "system_name": "Test",
                "bus_data": [[1, 1, 1.0, 0, 0, 0, 0, 0, 0, 0, -999, 999],
                             [1, 3, 1.0, 0, 0, 0, 0, 0, 0, 0, -999, 999]],
                "line_data": [[1, 2, 0.02, 0.06, 0.0, 1.0, 0.0]],
            })

    def test_no_slack_bus(self):
        with pytest.raises(ValueError, match="exactly 1 slack"):
            model.prepare_model({
                "system_name": "Test",
                "bus_data": [[1, 3, 1.0, 0, 0, 0, 0.2, 0.1, 0, 0, -999, 999]],
                "line_data": [],
            })

    def test_zero_voltage_bus(self):
        with pytest.raises(ValueError, match="positive"):
            model.prepare_model({
                "system_name": "Test",
                "bus_data": [[1, 1, 0.0, 0, 0, 0, 0, 0, 0, 0, -999, 999]],
                "line_data": [],
            })

    def test_zero_impedance_line(self):
        with pytest.raises(ValueError, match="zero impedance"):
            model.prepare_model({
                "system_name": "Test",
                "bus_data": [[1, 1, 1.0, 0, 0, 0, 0, 0, 0, 0, -999, 999],
                             [2, 3, 1.0, 0, 0, 0, 0.2, 0.1, 0, 0, -999, 999]],
                "line_data": [[1, 2, 0.0, 0.0, 0.0, 1.0, 0.0]],
            })

    def test_line_references_unknown_bus(self):
        with pytest.raises(ValueError, match="non-existent"):
            model.prepare_model({
                "system_name": "Test",
                "bus_data": [[1, 1, 1.0, 0, 0, 0, 0, 0, 0, 0, -999, 999]],
                "line_data": [[1, 99, 0.02, 0.06, 0.0, 1.0, 0.0]],
            })
