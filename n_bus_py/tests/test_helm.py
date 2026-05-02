"""Test HELM and HELM-NR Hybrid solvers."""

import numpy as np
import pytest

from pfsolver import helm, helm_nr_hybrid


class TestHELM:
    @pytest.fixture(scope="class")
    def result(self, case_data_dict):
        return helm.solve(case_data_dict)

    def test_runs(self, result):
        assert "error" not in result

    def test_voltage_reasonable(self, result):
        V = result["bus_voltage"]
        # HELM may not converge perfectly but voltages should be reasonable
        assert np.all(V >= 0.85)
        assert np.all(V <= 1.15)

    def test_no_nan(self, result):
        assert not np.isnan(result["bus_voltage"]).any()
        assert not np.isinf(result["bus_voltage"]).any()

    def test_germ_produces_finite(self, case_data_dict):
        from pfsolver.model import prepare_model
        from pfsolver.holomorphic import compute_germ
        m = prepare_model(case_data_dict)
        V0 = compute_germ(m)
        assert V0.shape == (5,)
        assert np.isfinite(V0).all()
        assert abs(V0[0]) == pytest.approx(1.06)  # slack


class TestHELMNRHybrid:
    @pytest.fixture(scope="class")
    def result(self, case_data_dict):
        return helm_nr_hybrid.solve(case_data_dict)

    def test_converges(self, result):
        assert result["converged"] is True

    def test_p_loss_matches_nr(self, result):
        assert result["P_loss_total"] == pytest.approx(0.059374, rel=0.01)

    def test_voltage_reasonable(self, result):
        V = result["bus_voltage"]
        assert np.all(V >= 0.94)
        assert np.all(V <= 1.07)
