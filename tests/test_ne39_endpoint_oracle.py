"""ตรวจ oracle stamp/steady droop/fail-closed แยกจาก MATLAB production."""
from pathlib import Path
import sys
import unittest

import numpy as np

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'/'diagnostics'))
from screen_ne39_chronology_design import network, solve_gfm, record


class EndpointOracleTests(unittest.TestCase):
    def test_transformer_stamp_and_shunt_sign(self):
        bus=np.zeros((2,13)); bus[:,0]=[1,2]; bus[0,5]=-200
        branch=np.zeros((1,13)); branch[0,[0,1,2,3,4,8,9,10]]=[1,2,.01,.1,.02,1.1,10,1]
        y=network(bus,branch); a=1.1*np.exp(1j*np.deg2rad(10)); ys=1/complex(.01,.1)
        expected=np.array([[(ys+.01j)/abs(a)**2-2j,-ys/a.conjugate()],[-ys/a,ys+.01j]])
        np.testing.assert_allclose(y,expected,atol=1e-13)

    def test_common_droop_does_not_refloat_reference_power(self):
        v,i,error,w=solve_gfm(np.array([[1+0j]]),np.array([0]),0,np.array([1.2]),
                            np.array([0.]),np.array([1.]),np.array([1.]),.025,
                            np.array([1+0j]),dv=20)
        self.assertLess(error,1e-7); self.assertAlmostEqual(w,.01,places=9)
        self.assertAlmostEqual((v*np.conj(i))[0].real,1,places=9)
        self.assertAlmostEqual(1.2-20*w,1,places=9)

    def test_dc_fold_cannot_be_reported_as_pass(self):
        row=record(np.array([1+0j]),np.array([3+0j]),np.array([[3+0j]]),
                   np.array([0]),np.array([100.]),np.array([400.]),np.array([400.]),
                   np.array([[1.,10.]]))
        self.assertFalse(row['pass']); self.assertIn('IBR1:dc_steady_envelope',row['failures'])


if __name__=='__main__':
    unittest.main()
