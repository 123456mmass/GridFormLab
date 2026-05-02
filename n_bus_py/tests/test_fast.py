"""Test fast methods: FDLF, DC Power Flow, Dishonest NR."""

import numpy as np
import pytest

from pfsolver import fast_decoupled, dc_power_flow, dishonest_nr


class TestFastDecoupled:
    @pytest.fixture(scope="class")
    def result(self, case_data_dict):
        return fast_decoupled.solve(case_data_dict)

    def test_converges(self, result):
        assert result["converged"] is True

    def test_iterations(self, result):
        assert 5 <= result["iterations"] <= 25

    def test_p_loss_close_to_nr(self, result):
        assert result["P_loss_total"] == pytest.approx(0.059374, rel=0.04)

    def test_voltage_reasonable(self, result):
        V = result["bus_voltage"]
        assert np.all(V >= 0.94)
        assert np.all(V <= 1.07)

    def test_slack_angle_zero(self, result):
        assert abs(result["bus_angle_deg"][0]) < 1e-6

    def test_no_nan(self, result):
        assert not np.isnan(result["bus_voltage"]).any()


class TestDCPowerFlow:
    @pytest.fixture(scope="class")
    def result(self, case_data_dict):
        return dc_power_flow.solve(case_data_dict)

    def test_converges(self, result):
        assert result["converged"] is True

    def test_single_iteration(self, result):
        assert result["iterations"] == 1

    def test_voltage_near_1pu(self, result):
        V = result["bus_voltage"]
        assert np.all(V >= 0.99)
        assert np.all(V <= 1.01)

    def test_slack_angle_zero(self, result):
        assert abs(result["bus_angle_deg"][0]) < 1e-6

    def test_no_nan(self, result):
        assert not np.isnan(result["bus_voltage"]).any()


class TestDishonestNR:
    @pytest.fixture(scope="class")
    def result(self, case_data_dict):
        return dishonest_nr.solve(case_data_dict)

    def test_converges(self, result):
        assert result["converged"] is True

    def test_p_loss_matches_nr(self, result):
        assert result["P_loss_total"] == pytest.approx(0.059374, rel=0.01)

    def test_voltage_reasonable(self, result):
        V = result["bus_voltage"]
        assert np.all(V >= 0.94)
        assert np.all(V <= 1.07)
