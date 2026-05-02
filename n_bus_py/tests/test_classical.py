"""Test classical solvers: Newton-Raphson and Gauss-Seidel."""

import numpy as np
import pytest

from pfsolver import newton_raphson, gauss_seidel


class TestNewtonRaphson:
    @pytest.fixture(scope="class")
    def result(self, case_data_dict):
        return newton_raphson.solve(case_data_dict)

    def test_converges(self, result):
        assert result["converged"] is True

    def test_iterations(self, result):
        assert 3 <= result["iterations"] <= 10

    def test_p_loss_matches_benchmark(self, result):
        # IEEE 5-bus benchmark: P_loss = 0.059374 pu
        assert result["P_loss_total"] == pytest.approx(0.059374, rel=0.01)

    def test_voltage_near_1pu(self, result):
        V = result["bus_voltage"]
        assert np.all(V >= 0.94)
        assert np.all(V <= 1.07)

    def test_slack_voltage(self, result):
        assert result["bus_voltage"][0] == pytest.approx(1.06, rel=1e-4)

    def test_pv_voltage(self, result):
        assert result["bus_voltage"][1] == pytest.approx(1.00, rel=1e-4)

    def test_slack_angle_zero(self, result):
        assert abs(result["bus_angle_deg"][0]) < 1e-6

    def test_power_balance(self, result):
        mismatch = abs(result["P_total_gen"] - result["P_total_load"] - result["P_loss_total"])
        assert mismatch < 0.001

    def test_no_nan(self, result):
        assert not np.isnan(result["bus_voltage"]).any()
        assert not np.isnan(result["bus_angle"]).any()

    def test_line_flows_finite(self, result):
        assert np.isfinite(result["line_flow_P"]).all()
        assert np.isfinite(result["line_flow_Q"]).all()

    def test_mismatch_decreasing(self, result):
        hist = result["mismatch_history"]
        assert len(hist) > 0
        # Mismatch should generally decrease
        assert hist[-1] < hist[0]

    def test_metadata_present(self, result):
        meta = result["metadata"]
        assert meta["num_buses"] == 5
        assert meta["num_lines"] == 7


class TestGaussSeidel:
    @pytest.fixture(scope="class")
    def result(self, case_data_dict):
        return gauss_seidel.solve(case_data_dict, {"max_iter": 500, "tolerance": 1e-6, "acceleration": 1.4})

    def test_runs(self, result):
        assert "error" not in result

    def test_voltage_reasonable(self, result):
        V = result["bus_voltage"]
        assert np.all(V >= 0.90)
        assert np.all(V <= 1.10)

    def test_no_nan(self, result):
        assert not np.isnan(result["bus_voltage"]).any()
