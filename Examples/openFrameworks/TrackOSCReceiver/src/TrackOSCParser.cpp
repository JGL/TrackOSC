#include "TrackOSCParser.h"

#include "ofUtils.h"
#include <stdexcept>

namespace trackosc {

const std::vector<std::string> ALL_ADDRESSES = {
    "/camerainfo", "/poses/arr", "/hands/arr", "/faces/arr", "/faces/box", "/faces/contour",
    "/texts/arr", "/animals/arr", "/poses3d/arr", "/barcodes/arr", "/animalposes/arr", "/humans/arr"};

bool isKeypointAddress(const std::string& address) { return keypointCount(address) > 0; }

int keypointCount(const std::string& address) {
    if (address == "/poses/arr") return 17;
    if (address == "/hands/arr") return 21;
    if (address == "/faces/arr") return 76;
    if (address == "/animalposes/arr") return 25;
    return 0;
}

std::string CameraInfo::orientationName() const {
    switch (orientation) {
        case 0: return "landscape";
        case 90: return "portrait";
        case 180: return "landscape (flipped)";
        case 270: return "portrait (upside down)";
        default: return ofToString(orientation) + "°";
    }
}

int Frame::detectionCount() const {
    return int(keypoints.size() + boxes.size() + faceBoxes.size() + contours.size() + poses3D.size() + barcodes.size());
}

namespace {

/// The running-argument-cursor idiom over an ofxOscMessage, with bounds checks.
class Cursor {
public:
    explicit Cursor(const ofxOscMessage& m) : message(m) {}

    int32_t i32() { check(); return message.getArgAsInt32(index++); }
    int32_t count() {
        int32_t n = i32();
        if (n < 0) throw std::runtime_error(message.getAddress() + ": negative count");
        return n;
    }
    float f() { check(); return message.getArgAsFloat(index++); }
    std::string s() { check(); return message.getArgAsString(index++); }
    Rect rect() { Rect r; r.left = f(); r.top = f(); r.width = f(); r.height = f(); return r; }

private:
    void check() const {
        if (index >= message.getNumArgs()) {
            throw std::runtime_error(message.getAddress() + ": truncated (expected >= " + ofToString(index + 1) +
                                     " arguments, got " + ofToString(message.getNumArgs()) + ")");
        }
    }
    const ofxOscMessage& message;
    std::size_t index = 0;
};

}  // namespace

CameraInfo parseCameraInfo(const ofxOscMessage& message) {
    Cursor cur(message);
    CameraInfo info;
    info.width = cur.i32();
    info.height = cur.i32();
    info.orientation = cur.i32();
    info.facing = cur.i32();
    info.at = ofGetElapsedTimef();
    return info;
}

Frame parseFrame(const ofxOscMessage& message) {
    const std::string address = message.getAddress();
    Cursor cur(message);
    Frame frame;
    frame.address = address;
    frame.frameW = cur.i32();
    frame.frameH = cur.i32();
    frame.at = ofGetElapsedTimef();
    const int32_t n = cur.count();

    if (isKeypointAddress(address)) {
        const int count = keypointCount(address);
        for (int32_t i = 0; i < n; i++) {
            Keypoints k;
            k.confidence = cur.f();
            k.points.reserve(count);
            for (int j = 0; j < count; j++) {
                Point p;
                p.x = cur.f(); p.y = cur.f(); p.c = cur.f();
                k.points.push_back(p);
            }
            frame.keypoints.push_back(std::move(k));
        }
    } else if (address == "/texts/arr" || address == "/animals/arr") {
        for (int32_t i = 0; i < n; i++) {
            Box b;
            b.confidence = cur.f(); b.box = cur.rect(); b.label = cur.s();
            frame.boxes.push_back(std::move(b));
        }
    } else if (address == "/humans/arr") {
        for (int32_t i = 0; i < n; i++) {
            Box b;
            b.confidence = cur.f(); b.box = cur.rect(); b.label = "human";
            frame.boxes.push_back(std::move(b));
        }
    } else if (address == "/faces/box") {
        for (int32_t i = 0; i < n; i++) {
            FaceBox fb;
            fb.confidence = cur.f(); fb.box = cur.rect();
            fb.roll = cur.f(); fb.yaw = cur.f(); fb.pitch = cur.f();
            frame.faceBoxes.push_back(fb);
        }
    } else if (address == "/faces/contour") {
        for (int32_t i = 0; i < n; i++) {
            Contour c;
            c.confidence = cur.f();
            const int32_t m = cur.count();   // varies per face – always loop on m
            for (int32_t j = 0; j < m; j++) { float x = cur.f(); float y = cur.f(); c.points.emplace_back(x, y); }
            frame.contours.push_back(std::move(c));
        }
    } else if (address == "/poses3d/arr") {
        for (int32_t i = 0; i < n; i++) {
            Pose3D p;
            p.confidence = cur.f(); p.bodyHeight = cur.f();
            for (int j = 0; j < 17; j++) {
                Joint3D joint;
                joint.x = cur.f(); joint.y = cur.f(); joint.z = cur.f(); joint.px = cur.f(); joint.py = cur.f();
                p.joints.push_back(joint);
            }
            frame.poses3D.push_back(std::move(p));
        }
    } else if (address == "/barcodes/arr") {
        for (int32_t i = 0; i < n; i++) {
            Barcode b;
            b.confidence = cur.f(); b.box = cur.rect();
            for (int j = 0; j < 4; j++) { float x = cur.f(); float y = cur.f(); b.corners.emplace_back(x, y); }
            b.symbology = cur.s(); b.payload = cur.s();
            frame.barcodes.push_back(std::move(b));
        }
    } else {
        throw std::runtime_error(address + ": not a TrackOSC address");
    }
    return frame;
}

}  // namespace trackosc
