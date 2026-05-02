"""Test continuation methods: Homotopy, CPF PC, CPF LS."""

import numpy as np
import pytest

from pfsolver import dynamic_homotopy, cpf_pc, cpf_ls


class TestDynamicHomotopy:
    @pytest.fixture(scope="class")
    def result(self, case_data_dict):
        return dynamic_homotopy.solve(case_data_dict)

    def test_converges(self, result):
        assert result["converged"] is True

    def test_lambda_final(self, result):
        assert result["homotopy_final_lambda"] == pytest.approx(1.0, abs=0.05)

    def test_p_loss_matches_nr(self, result):
        assert result["P_loss_total"] == pytest.approx(0.059374, rel=0.01)

    def test_voltage_reasonable(self, result):
        V = result["bus_voltage"]
        assert np.all(V >= 0.94)
        assert np.all(V <= 1.07)


class TestCPFPC:
    @pytest.fixture(scope="class")
    def result(self, case_data_dict):
        return cpf_pc.solve(case_data_dict)

    def test_runs(self, result):
        assert "error" not in result

    def test_has_pv_curve(self, result):
        assert "cpf_pv_curve" in result
        assert len(result["cpf_pv_curve"]) >= 2

    def test_pv_curve_data_valid(self, result):
        for lam, v in result["cpf_pv_curve"]:
            assert isinstance(lam, (int, float))
            assert isinstance(v, (int, float))
            assert lam >= 0
            assert v > 0

    def test_no_nan(self, result):
        if result.get("bus_voltage") is not None:
            assert not np.isnan(result["bus_voltage"]).any()


class TestCPFLS:
    @pytest.fixture(scope="class")
    def result(self, case_data_dict):
        return cpf_ls.solve(case_data_dict)

    def test_runs(self, result):
        assert "error" not in result
