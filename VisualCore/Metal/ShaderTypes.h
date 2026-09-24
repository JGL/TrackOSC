//
//  ShaderTypes.h
//  TrackOSC (VisualCore)
//
//  Shared between Swift (bridging header) and Metal: the scene as the GPU
//  sees it. Coordinates are the scene's normalised 0–1 space (x across,
//  y down); shaders map them into the view with sceneOrigin/sceneSize.
//

#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>

#define VC_MAX_PERSONS 8
#define VC_BODY_JOINTS 17
#define VC_MAX_HANDS 8
#define VC_HAND_JOINTS 21
#define VC_MAX_FACES 4
#define VC_MAX_PARAMS 16
#define VC_MAX_PALETTE 8
#define VC_FACE_LANDMARKS 76
#define VC_MAX_ANIMALS 4
#define VC_ANIMAL_JOINTS 25

typedef struct {
    vector_float2 joints[VC_BODY_JOINTS];
    float visible[VC_BODY_JOINTS];
    vector_float2 velocities[VC_BODY_JOINTS];
    vector_float2 centroid;
    vector_float2 boxMin;
    vector_float2 boxMax;
    float id;
    float age;
    float confidence;
    float speed;
} GPUPerson;

typedef struct {
    vector_float2 joints[VC_HAND_JOINTS];
    float visible[VC_HAND_JOINTS];
    vector_float2 centre;
    float openness;
    float isLeft;     // 1 left, 0 right, -1 unknown
    float person;     // owning person id, or -1
    float _pad;
} GPUHand;

typedef struct {
    vector_float2 centre;
    vector_float2 size;
    float yaw;
    float pitch;
    float roll;
    float mouth;
    float person;
    float hasLandmarks;   // 1 when `landmarks` holds the 76 points
    float _pad[2];
    vector_float2 landmarks[VC_FACE_LANDMARKS];
} GPUFace;

typedef struct {
    vector_float2 joints[VC_ANIMAL_JOINTS];
    float visible[VC_ANIMAL_JOINTS];
    vector_float2 centroid;
    float id;
    float age;
    float confidence;
    float speed;
    float _pad;
} GPUAnimal;

/// One sprite: a soft dot (kind 0) or a glyph from the atlas (kind 1),
/// drawn as a quad of `size` pixels rotated by `rotation`, in scene uv.
typedef struct {
    vector_float2 position;      // scene uv (0–1, y down)
    vector_float2 size;          // pixels
    vector_float4 color;         // premultiplied brightness; alpha = opacity
    vector_float4 uv;            // atlas rect u0 v0 u1 v1 (glyphs)
    float rotation;              // radians
    float kind;                  // 0 dot, 1 glyph, 2 ring
    float softness;              // dots: 0 hard … 1 soft
    float _pad;
} GPUSprite;

typedef struct {
    vector_float2 position;      // scene uv
    vector_float4 color;
} GPULineVertex;

typedef struct {
    vector_float2 resolution;    // pixels
    vector_float2 sceneOrigin;   // uv of the scene's top-left
    vector_float2 sceneSize;     // uv extent of the scene
    float time;
    float dt;
    float aspect;                // view width / height
    float presence;
    float activity;
    float isAttract;
    int personCount;
    int handCount;
    int faceCount;
    int frame;
    float params[VC_MAX_PARAMS];
    vector_float4 palette[VC_MAX_PALETTE];
    int paletteCount;
    float vignette;
    float grain;
    float gamma;
    float feedbackAvailable;
    float seed;
    int animalCount;
    float _pad;
} SceneUniforms;

#endif
