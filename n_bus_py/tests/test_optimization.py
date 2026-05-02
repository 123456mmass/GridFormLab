"""Test optimization methods: Economic Dispatch and AC OPF."""

import pytest

from pfsolver import economic_dispatch, ac_opf


class TestEconomicDispatch:
    @pytest.fixture(scope="class")
    def result(self, case_data_dict):
        return economic_dispatch.solve(case_data_dict)

    def test_converges(self, result):
        assert result["converged"] is True

    def test_power_balance(self, result):
        mismatch = abs(result["P_dispatched"] - result["P_target"])
        assert mismatch < 0.01

    def test_lambda_positive(self, result):
        assert result["lambda"] > 0

    def test_total_cost_reasonable(self, result):
        assert result["total_cost"] > 0

    def test_generation_within_limits(self, result):
        P_gen = result["P_generation"]
        P_min = result["P_min"]
        P_max = result["P_max"]
        for i in range(len(P_gen)):
            assert P_gen[i] >= P_min[i] - 0.01
            assert P_gen[i] <= P_max[i] + 0.01

    def test_incremental_cost_equal_for_active(self, result):
        ic = result["incremental_cost"]
        active = result["active_generators"]
        if sum(active) >= 2:
            ic_active = [ic[i] for i in range(len(ic)) if active[i]]
            ref = ic_active[0]
            for v in ic_active:
                assert abs(v - ref) < 0.1


class TestACOPF:
    @pytest.fixture(scope="class")
    def result(self, case_data_dict):
        return ac_opf.solve(case_data_dict)

    def test_runs(self, result):
        assert "error" not in result

    def test_converged_or_not(self, result):
        assert "converged" in result
