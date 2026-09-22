// TrackOSC message parsing for openFrameworks (ofxOsc) – no drawing here.
//
// Every detection message starts with int32 width, int32 height, int32 n
// (pixels of the sent frame, origin top-left, never mirrored), then n
// detections whose layout depends on the address – see the root README
// "OSC wire format". A keypoint with c == 0 is missing (VisionOSC's
// sentinel) – skip it.
#pragma once

#include "ofVectorMath.h"
#include "ofxOsc.h"
#include <cstdint>
#include <string>
#include <vector>

namespace trackosc {

struct Point { float x = 0, y = 0, c = 0; };
struct Rect { float left = 0, top = 0, width = 0, height = 0; };
struct Joint3D { float x = 0, y = 0, z = 0, px = 0, py = 0; };  // metres, then pixels

struct Keypoints { float confidence = 0; std::vector<Point> points; };          // poses, hands, faces, animal poses
struct Box { float confidence = 0; Rect box; std::string label; };              // texts, animals, humans ("human")
struct FaceBox { float confidence = 0; Rect box; float roll = 0, yaw = 0, pitch = 0; };
struct Contour { float confidence = 0; std::vector<glm::vec2> points; };        // open jawline; may be empty
struct Pose3D { float confidence = 0, bodyHeight = 0; std::vector<Joint3D> joints; };
struct Barcode { float confidence = 0; Rect box; std::vector<glm::vec2> corners; std::string symbology, payload; };

struct CameraInfo {
    int width = 0, height = 0, orientation = 0, facing = 0;
    float at = 0;
    std::string orientationName() const;
};

/// One decoded detection message: the header plus one vector per kind (only
/// the vector matching `address` is filled).
struct Frame {
    std::string address;
    int frameW = 0, frameH = 0;
    float at = 0;   // ofGetElapsedTimef() when received
    std::vector<Keypoints> keypoints;
    std::vector<Box> boxes;
    std::vector<FaceBox> faceBoxes;
    std::vector<Contour> contours;
    std::vector<Pose3D> poses3D;
    std::vector<Barcode> barcodes;
    int detectionCount() const;
};

/// Throws std::runtime_error on a truncated or malformed message.
Frame parseFrame(const ofxOscMessage& message);
CameraInfo parseCameraInfo(const ofxOscMessage& message);

bool isKeypointAddress(const std::string& address);
int keypointCount(const std::string& address);   // 17, 21, 76, 25
extern const std::vector<std::string> ALL_ADDRESSES;

inline bool visible(const Point& p) { return p.c > 0; }

}  // namespace trackosc
