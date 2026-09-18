"""Exercises trackosc_callbacks.py outside TouchDesigner with stub op()/mod.

    cd Examples/TouchDesigner && python3 -m unittest discover tests
"""

import builtins
import importlib.util
import os
import sys
import types
import unittest

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class FakeTable:
    def __init__(self):
        self.rows = []

    def clear(self):
        self.rows = []

    def appendRow(self, row):
        self.rows.append(list(row))

    @property
    def numRows(self):
        return len(self.rows)


class CallbackTests(unittest.TestCase):
    def setUp(self):
        self.tables = {}
        builtins.op = lambda name: self.tables.setdefault(name, FakeTable())
        skeletons = self._load("trackosc_skeletons")
        builtins.mod = types.SimpleNamespace(trackosc_skeletons=skeletons)
        self.callbacks = self._load("trackosc_callbacks")

    def tearDown(self):
        del builtins.op
        del builtins.mod

    @staticmethod
    def _load(name):
        spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, name + ".py"))
        module = importlib.util.module_from_spec(spec)
        sys.modules[name] = module
        spec.loader.exec_module(module)
        return module

    def receive(self, address, args):
        self.callbacks.onReceiveOSC(None, 0, None, b"", 0, address, list(args), None)

    def test_poses_table(self):
        args = [720, 1280, 1, 0.95]
        for j in range(17):
            args += [0.0, 1280.0, 0.0] if j == 3 else [j * 10.0, j * 20.0, 0.9]
        self.receive("/poses/arr", args)
        rows = self.tables["poses"].rows
        self.assertEqual(rows[0], ["det", "joint", "name", "x", "y", "c", "conf"])
        self.assertEqual(len(rows), 1 + 17)
        self.assertEqual(rows[1][:3], [0, 0, "nose"])
        self.assertEqual(rows[4][2], "leftEar")
        self.assertEqual(rows[4][5], 0.0)  # missing sentinel keeps c == 0
        self.assertEqual(self.tables["frames"].rows[1][:4], ["/poses/arr", 720, 1280, 1])

    def test_camerainfo_and_barcodes_and_contours(self):
        self.receive("/camerainfo", [720, 1280, 90, 1])
        self.assertEqual(self.tables["camerainfo"].rows[3], ["orientation", 90])

        args = [720, 1280, 1, 1.0, 10.0, 20.0, 30.0, 40.0, 10.0, 20.0, 40.0, 20.0, 40.0, 60.0, 10.0, 60.0, "QR", "hello"]
        self.receive("/barcodes/arr", args)
        row = self.tables["barcodes"].rows[1]
        self.assertEqual(row[-2:], ["QR", "hello"])
        self.assertEqual(row[6:8], [10.0, 20.0])  # tl_x, tl_y

        self.receive("/faces/contour", [720, 1280, 2, 0.9, 2, 1.0, 2.0, 3.0, 4.0, 0.5, 0])
        rows = self.tables["faces_contour"].rows
        self.assertEqual(len(rows), 1 + 2)  # second face has m=0
        self.assertEqual(rows[2][:4], [0, 1, 3.0, 4.0])

    def test_poses3d_rows_carry_height(self):
        args = [720, 1280, 1, 0.93, 1.75]
        for j in range(17):
            args += [j * 0.1, j * 0.2, -2.0, j * 10.0, j * 20.0]
        self.receive("/poses3d/arr", args)
        rows = self.tables["poses3d"].rows
        self.assertEqual(rows[0][-1], "bodyHeight")
        self.assertEqual(rows[1][2], "root")
        self.assertAlmostEqual(rows[2][-1], 1.75)
        self.assertAlmostEqual(rows[2][5], -2.0)  # z

    def test_bad_input_is_logged_not_raised(self):
        self.receive("/poses/arr", [720, 1280, 1])       # truncated
        self.receive("/foo/bar", [1, 2, 3])               # unknown: ignored
        self.assertNotIn("foo", self.tables)


if __name__ == "__main__":
    unittest.main()
