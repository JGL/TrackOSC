"""Round-trips every TrackOSC message through python-osc's encoder and our parser.

    cd Examples/Python && python3 -m unittest discover tests
"""

import unittest

from pythonosc.osc_message import OscMessage
from pythonosc.osc_message_builder import OscMessageBuilder

from trackosc import (ANIMAL_EDGES, BODY_EDGES, HAND_EDGES, POSE3D_EDGES, Barcode, Box,
                      CameraInfo, Contour, FaceBox, Keypoints, Pose3D, TruncatedMessage,
                      parse_message, visible)


def roundtrip(address, args):
    """Encode with python-osc (int → int32, float → float32, str → string) and re-parse."""
    builder = OscMessageBuilder(address=address)
    for value in args:
        builder.add_arg(value)
    message = OscMessage(builder.build().dgram)
    return parse_message(message.address, message.params)


def keypoints(n_points, n=1):
    args = [720, 1280, n]
    for i in range(n):
        args.append(0.9)
        for j in range(n_points):
            # every fifth point missing
            args += [0.0, 1280.0, 0.0] if j % 5 == 4 else [float(j * 10 + i), float(j * 20 + i), 0.5]
    return args


class ParseTests(unittest.TestCase):
    def test_camerainfo(self):
        info = roundtrip("/camerainfo", [720, 1280, 90, 1])
        self.assertIsInstance(info, CameraInfo)
        self.assertEqual((info.width, info.height, info.orientation, info.facing), (720, 1280, 90, 1))
        self.assertEqual(info.orientation_name, "portrait")

    def test_keypoint_kinds(self):
        for address, count in (("/poses/arr", 17), ("/hands/arr", 21), ("/faces/arr", 76), ("/animalposes/arr", 25)):
            frame = roundtrip(address, keypoints(count, n=2))
            self.assertEqual(frame.address, address)
            self.assertEqual((frame.frame_w, frame.frame_h), (720, 1280))
            self.assertEqual(len(frame.detections), 2)
            d = frame.detections[1]
            self.assertIsInstance(d, Keypoints)
            self.assertEqual(len(d.points), count)
            self.assertAlmostEqual(d.points[1].x, 11.0)
            self.assertFalse(visible(d.points[4]))
            self.assertTrue(visible(d.points[0]))

    def test_empty_frame_keeps_header(self):
        frame = roundtrip("/poses/arr", [1280, 720, 0])
        self.assertEqual((frame.frame_w, frame.frame_h, frame.detections), (1280, 720, []))

    def test_boxes(self):
        frame = roundtrip("/texts/arr", [720, 1280, 2, 0.8, 1.0, 2.0, 3.0, 4.0, "HELLO", 0.7, 5.0, 6.0, 7.0, 8.0, "WORLD"])
        self.assertEqual([d.label for d in frame.detections], ["HELLO", "WORLD"])
        self.assertEqual(frame.detections[1].box.left, 5.0)
        humans = roundtrip("/humans/arr", [720, 1280, 1, 0.97, 10.0, 20.0, 30.0, 40.0])
        self.assertIsInstance(humans.detections[0], Box)
        self.assertEqual(humans.detections[0].label, "human")
        self.assertEqual(humans.detections[0].box.height, 40.0)

    def test_face_box_and_contour(self):
        box = roundtrip("/faces/box", [720, 1280, 1, 0.9, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0])
        d = box.detections[0]
        self.assertIsInstance(d, FaceBox)
        self.assertEqual((d.roll, d.yaw, d.pitch), (5.0, 6.0, 7.0))
        contour = roundtrip("/faces/contour", [720, 1280, 2, 0.9, 2, 1.0, 2.0, 3.0, 4.0, 0.5, 0])
        first, second = contour.detections
        self.assertIsInstance(first, Contour)
        self.assertEqual(first.points, [(1.0, 2.0), (3.0, 4.0)])
        self.assertEqual(second.points, [])

    def test_poses3d(self):
        args = [720, 1280, 1, 0.93, 1.75]
        for j in range(17):
            args += [j * 0.1, j * 0.2, -2.0, j * 10.0, j * 20.0]
        frame = roundtrip("/poses3d/arr", args)
        d = frame.detections[0]
        self.assertIsInstance(d, Pose3D)
        self.assertAlmostEqual(d.body_height, 1.75)
        self.assertEqual(len(d.joints), 17)
        self.assertAlmostEqual(d.joints[3].x, 0.3, places=5)
        self.assertAlmostEqual(d.joints[3].py, 60.0)

    def test_barcodes(self):
        args = [720, 1280, 2,
                1.0, 10.0, 20.0, 30.0, 40.0, 10.0, 20.0, 40.0, 20.0, 40.0, 60.0, 10.0, 60.0, "QR", "https://github.com/JGL/TrackOSC",
                0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, "EAN13", ""]
        frame = roundtrip("/barcodes/arr", args)
        first, second = frame.detections
        self.assertIsInstance(first, Barcode)
        self.assertEqual(first.corners, [(10.0, 20.0), (40.0, 20.0), (40.0, 60.0), (10.0, 60.0)])
        self.assertEqual((first.symbology, first.payload), ("QR", "https://github.com/JGL/TrackOSC"))
        self.assertEqual((second.symbology, second.payload), ("EAN13", ""))

    def test_unknown_address_is_none(self):
        self.assertIsNone(roundtrip("/foo/bar", [1, 2, 0]))

    def test_truncated_raises(self):
        with self.assertRaises(TruncatedMessage):
            roundtrip("/poses/arr", [720, 1280, 1])
        with self.assertRaises(TruncatedMessage):
            roundtrip("/barcodes/arr", [720, 1280, 1] + [0.0] * 13 + ["QR"])

    def test_negative_count_raises(self):
        with self.assertRaises(ValueError):
            roundtrip("/humans/arr", [720, 1280, -1])

    def test_edge_lists_index_their_joint_lists(self):
        for edges, count in ((BODY_EDGES, 17), (HAND_EDGES, 21), (POSE3D_EDGES, 17), (ANIMAL_EDGES, 25)):
            for a, b in edges:
                self.assertTrue(0 <= a < count and 0 <= b < count and a != b, (edges, a, b))


if __name__ == "__main__":
    unittest.main()
