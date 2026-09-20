#pragma once

#include "TrackOSCParser.h"
#include "ofMain.h"
#include "ofxOsc.h"
#include <map>

class ofApp : public ofBaseApp {
public:
    void setup() override;
    void update() override;
    void draw() override;
    void keyPressed(int key) override;

private:
    static constexpr int PORT = 9527;
    static constexpr float STALE_S = 0.5f;
    static constexpr float CAMERA_INFO_STALE_S = 2.0f;

    ofxOscReceiver receiver;
    std::map<std::string, trackosc::Frame> latest;   // address → most recent frame
    trackosc::CameraInfo camera;
    bool hasCamera = false;
    int unknownMessages = 0;

    bool threeD = false;
    bool showGuides = true;
    ofEasyCam cam;

    void draw2D();
    void draw3D();
    void drawGuides(int frameW, int frameH, float sc, float ox, float oy);
    void drawSkeleton(const std::vector<trackosc::Point>& points, const std::vector<trackosc::Edge>& edges,
                      const ofColor& colour, float sc, float ox, float oy);
    void drawBox(const trackosc::Rect& box, const std::string& label, const ofColor& colour, float sc, float ox, float oy);
    bool fresh(const trackosc::Frame& frame) const;
};
