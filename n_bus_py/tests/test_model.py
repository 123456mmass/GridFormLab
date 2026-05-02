"""Test model preparation and Ybus construction."""

import numpy as np
import pytest


class TestModel:
    def test_prepare_model_structure(self, m):
        assert m.num_buses == 5
        assert m.num_lines == 7
        assert len(m.slack_buses) == 1
        assert m.slack_buses[0] == 0  # bus 1 (0-indexed)
        assert len(m.pv_buses) == 1
        assert m.pv_buses[0] == 1  # bus 2
        assert len(m.pq_buses) == 3

    def test_ybus_shape(self, m):
        assert m.Ybus.shape == (5, 5)
        assert np.isfinite(m.Ybus).all()

    def test_ybus_nonzero_diagonal(self, m):
        diag = np.abs(m.Ybus.diagonal())
        assert (diag > 0).all()

    def test_ybus_no_nan(self, m):
        assert not np.isnan(m.Ybus).any()
        assert not np.isinf(m.Ybus).any()

    def test_bus_data_loads(self, m):
        total_load = np.sum(m.P_load)
        assert total_load == pytest.approx(1.65, rel=0.01)

    def test_external_bus_ids(self, m):
        assert list(m.external_bus_ids) == [1, 2, 3, 4, 5]

    def test_base_values(self, case_data):
        bv = case_data.get("base_values", {})
        assert bv.get("S_base_MVA") == 100


class TestCaseLoader:
    def test_load_ieee5bus(self, case_data_dict):
        assert case_data_dict["system_name"] == "IEEE 5-Bus System"
        assert len(case_data_dict["bus_data"]) == 5
        assert len(case_data_dict["line_data"]) == 7

    def test_list_cases(self):
        from cases.loader import list_cases
        cases = list_cases()
        assert "ieee5bus" in cases
