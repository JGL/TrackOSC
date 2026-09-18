// TrackOSC receiver for openFrameworks: draws all twelve messages in 2D like
// the Processing reference sketch, and /poses3d/arr in 3D (press 3) with an
// ofEasyCam over a floor grid. Press G to toggle the coordinate guides.

#include "ofApp.h"
#include "TrackOSCSkeletons.h"

using namespace trackosc;

void ofApp::setup() {
    ofSetWindowTitle("TrackOSC Receiver (openFrameworks) — listening on " + ofToString(PORT));
    ofSetFrameRate(60);
    ofBackground(0);
    receiver.setup(PORT);
    cam.setDistance(4);
    cam.setNearClip(0.05f);
    cam.setFarClip(100);
}

void ofApp::update() {
    while (receiver.hasWaitingMessages()) {
        ofxOscMessage message;
        receiver.getNextMessage(message);
        try {
            if (message.getAddress() == "/camerainfo") {
                camera = parseCameraInfo(message);
                hasCamera = true;
            } else {
                Frame frame = parseFrame(message);
                latest[frame.address] = std::move(frame);
            }
        } catch (const std::exception& error) {
            unknownMessages++;
            if (unknownMessages % 100 == 1) ofLogNotice("TrackOSC") << error.what();
        }
    }
}

bool ofApp::fresh(const Frame& frame) const { return ofGetElapsedTimef() - frame.at < STALE_S; }

void ofApp::draw() {
    if (threeD) draw3D(); else draw2D();
    ofSetColor(GUIDE_COLOUR);
    ofDrawBitmapString(std::string(threeD ? "3D" : "2D") + " · press 3/2 to switch · G guides · UDP " + ofToString(PORT) +
                       (unknownMessages ? "  unknown/undecodable: " + ofToString(unknownMessages) : ""), 10, ofGetHeight() - 10);
}

// ---- 2D ----

void ofApp::draw2D() {
    const Frame* ref = nullptr;
    for (const auto& [address, frame] : latest) if (fresh(frame)) { ref = &frame; break; }
    if (!ref) {
        ofSetColor(GUIDE_COLOUR);
        ofDrawBitmapString("Waiting for OSC messages on port " + ofToString(PORT) + "...", ofGetWidth() / 2 - 150, ofGetHeight() / 2);
        return;
    }
    const int frameW = ref->frameW, frameH = ref->frameH;
    const float sc = std::min(ofGetWidth() / float(frameW), ofGetHeight() / float(frameH));
    const float ox = (ofGetWidth() - frameW * sc) / 2, oy = (ofGetHeight() - frameH * sc) / 2;
    auto X = [&](float x) { return ox + x * sc; };
    auto Y = [&](float y) { return oy + y * sc; };

    if (showGuides) drawGuides(frameW, frameH, sc, ox, oy);
    ofSetLineWidth(2);

    for (const auto& [address, frame] : latest) {
        if (!fresh(frame)) continue;
        if (address == "/humans/arr") for (const auto& b : frame.boxes) drawBox(b.box, b.label + " " + ofToString(b.confidence, 2), HUMAN_COLOUR, sc, ox, oy);
        if (address == "/texts/arr") for (const auto& b : frame.boxes) drawBox(b.box, b.label + " " + ofToString(b.confidence, 2), TEXT_COLOUR, sc, ox, oy);
        if (address == "/animals/arr") for (const auto& b : frame.boxes) drawBox(b.box, b.label + " " + ofToString(b.confidence, 2), ANIMAL_COLOUR, sc, ox, oy);
        if (address == "/faces/box") for (const auto& fb : frame.faceBoxes) drawBox(fb.box, "", FACE_COLOUR, sc, ox, oy);
        if (address == "/poses/arr") for (const auto& k : frame.keypoints) drawSkeleton(k.points, BODY_EDGES, POSE_COLOUR, sc, ox, oy);
        if (address == "/hands/arr") for (const auto& k : frame.keypoints) drawSkeleton(k.points, HAND_EDGES, HAND_COLOUR, sc, ox, oy);
        if (address == "/animalposes/arr") for (const auto& k : frame.keypoints) drawSkeleton(k.points, ANIMAL_EDGES, ANIMALPOSE_COLOUR, sc, ox, oy);
        if (address == "/faces/arr") {
            ofSetColor(FACE_COLOUR);
            ofFill();
            for (const auto& k : frame.keypoints) for (const auto& p : k.points) if (visible(p)) ofDrawCircle(X(p.x), Y(p.y), 1.5f);
        }
        if (address == "/faces/contour") {
            ofSetColor(FACE_COLOUR);
            for (const auto& c : frame.contours) {
                ofPolyline line;
                for (const auto& p : c.points) line.addVertex(X(p.x), Y(p.y));
                line.draw();   // open jawline — never close it
            }
        }
        if (address == "/poses3d/arr") {
            for (const auto& pose : frame.poses3D) {
                std::vector<Point> projected;
                for (const auto& j : pose.joints) projected.push_back({j.px, j.py, 1});
                drawSkeleton(projected, POSE3D_EDGES, POSE3D_COLOUR, sc, ox, oy);
                ofSetColor(POSE3D_COLOUR);
                ofDrawBitmapString("z " + ofToString(pose.joints[0].z, 2) + " m  h " + ofToString(pose.bodyHeight, 2) + " m",
                                   X(pose.joints[0].px) + 8, Y(pose.joints[0].py) - 8);
            }
        }
        if (address == "/barcodes/arr") {
            ofSetColor(BARCODE_COLOUR);
            for (const auto& b : frame.barcodes) {
                ofPolyline quad;
                for (const auto& c : b.corners) quad.addVertex(X(c.x), Y(c.y));
                quad.close();
                ofNoFill();
                quad.draw();
                ofFill();
                ofDrawCircle(X(b.corners[0].x), Y(b.corners[0].y), 4);   // top-left corner
                ofDrawBitmapString(b.symbology + " " + b.payload, X(b.box.left), std::max(Y(b.box.top) - 6, 14.f));
            }
        }
    }
}

void ofApp::drawSkeleton(const std::vector<Point>& points, const std::vector<Edge>& edges, const ofColor& colour,
                         float sc, float ox, float oy) {
    ofSetColor(colour);
    for (const auto& [a, b] : edges) {
        if (a >= int(points.size()) || b >= int(points.size())) continue;
        if (!visible(points[a]) || !visible(points[b])) continue;   // missing keypoint
        ofDrawLine(ox + points[a].x * sc, oy + points[a].y * sc, ox + points[b].x * sc, oy + points[b].y * sc);
    }
    ofFill();
    for (const auto& p : points) if (visible(p)) ofDrawCircle(ox + p.x * sc, oy + p.y * sc, 3);
}

void ofApp::drawBox(const Rect& box, const std::string& label, const ofColor& colour, float sc, float ox, float oy) {
    ofSetColor(colour);
    ofNoFill();
    ofDrawRectangle(ox + box.left * sc, oy + box.top * sc, box.width * sc, box.height * sc);
    ofFill();
    if (!label.empty()) ofDrawBitmapString(label, ox + box.left * sc + 4, std::max(oy + box.top * sc - 4, 14.f));
}

void ofApp::drawGuides(int frameW, int frameH, float sc, float ox, float oy) {
    const float fw = frameW * sc, fh = frameH * sc;
    ofSetColor(GUIDE_COLOUR, 128);
    ofNoFill();
    ofSetLineWidth(1);
    ofDrawRectangle(ox, oy, fw, fh);
    ofSetColor(GUIDE_COLOUR);
    ofFill();
    ofDrawCircle(ox, oy, 4);
    ofDrawArrow(glm::vec3(ox, oy, 0), glm::vec3(ox + 48, oy, 0), 4);
    ofDrawArrow(glm::vec3(ox, oy, 0), glm::vec3(ox, oy + 48, 0), 4);
    ofDrawBitmapString("x", ox + 58, oy + 4);
    ofDrawBitmapString("y", ox - 4, oy + 62);
    ofDrawBitmapString("(0,0)", ox + 8, oy - 8);
    std::string caption = ofToString(frameW) + "x" + ofToString(frameH) + " px";
    if (hasCamera && ofGetElapsedTimef() - camera.at < CAMERA_INFO_STALE_S) {
        caption += " · " + camera.orientationName() + " · " + (camera.facing == 1 ? "front" : "back") + " camera";
    }
    ofDrawBitmapString(caption, ox + fw / 2 - caption.size() * 4, oy + fh - 8);
}

// ---- 3D ----

void ofApp::draw3D() {
    const auto it = latest.find("/poses3d/arr");
    const bool live = it != latest.end() && fresh(it->second);

    cam.begin();
    ofEnableDepthTest();
    // Vision camera space is right-handed, y up, like openFrameworks' 3D
    // space; the phone/Mac camera sits at the origin and a subject stands
    // ~2 m away along z.
    ofSetColor(90);
    ofSetLineWidth(1);
    ofPushMatrix();
    ofTranslate(0, -1.2f, 2.0f);
    ofRotateXDeg(90);
    ofDrawGridPlane(0.5f, 4, false);
    ofPopMatrix();
    ofDrawAxis(0.25f);                    // x red, y green, z blue at the camera
    ofSetColor(190);
    ofDrawBox(0, 0, 0, 0.08f, 0.05f, 0.03f);

    if (live) {
        ofSetColor(POSE3D_COLOUR);
        ofSetLineWidth(3);
        for (const auto& pose : it->second.poses3D) {
            for (const auto& [a, b] : POSE3D_EDGES) {
                const auto& ja = pose.joints[a];
                const auto& jb = pose.joints[b];
                ofDrawLine(ja.x, ja.y, ja.z, jb.x, jb.y, jb.z);
            }
            for (const auto& j : pose.joints) ofDrawSphere(j.x, j.y, j.z, 0.03f);
        }
    }
    ofDisableDepthTest();
    cam.end();

    ofSetColor(GUIDE_COLOUR);
    std::string hud = live ? "/poses3d/arr  n=" + ofToString(it->second.poses3D.size()) : "Waiting for /poses3d/arr (turn on 3D Body on the sender)";
    if (live) for (const auto& pose : it->second.poses3D) hud += "  height " + ofToString(pose.bodyHeight, 2) + " m";
    ofDrawBitmapString(hud, 10, 20);
    ofDrawBitmapString("metres · x right · y up · z: Vision camera space · drag to orbit, scroll to zoom", 10, 36);
}

void ofApp::keyPressed(int key) {
    if (key == '3') threeD = true;
    if (key == '2') threeD = false;
    if (key == 'g' || key == 'G') showGuides = !showGuides;
    if (key == 'r' || key == 'R') cam.reset();
}
