// The crowd and island scenes; mirrors godot/main.gd. Only the camera moves, on the same path in
// both engines, so the frame time is the engine's own work.
#include "Doriax.h"
#include "WindowLinux.h"
#include "json.hpp"
#include <GL/gl.h>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <thread>
#include <vector>

using namespace doriax;
using Json = nlohmann::json;
using Clock = std::chrono::steady_clock;

#if !defined(NDEBUG) || !defined(__OPTIMIZE__)
#error Benchmarks require an optimized Release build
#endif

namespace {
Scene scene;
std::unique_ptr<Camera> camera;
std::unique_ptr<Light> light;
Json spec, world;
std::string sceneName, output, shared;
std::vector<std::unique_ptr<Object>> objects;
std::vector<double> frameMs;
std::vector<unsigned int> draws;
std::vector<uint64_t> triangles;
Clock::time_point readyTime, previousTime, measureTime;
bool ready = false, measuring = false, finished = false, captureSent = false;
double warmup, duration, freezeAt = -1;

std::string env(const char* name, const std::string& fallback = "") {
    const char* value = std::getenv(name);
    return value ? value : fallback;
}
Vector3 v3(const Json& p) { return Vector3(p[0].get<float>(), p[1].get<float>(), p[2].get<float>()); }

Quaternion yaw(float degrees) {
    const float a = degrees * float(M_PI) / 180.0f;
    return Quaternion(std::cos(a * 0.5f), 0, std::sin(a * 0.5f), 0);
}

void placeCamera(double t) {
    if (freezeAt >= 0) t = freezeAt;
    const auto& c = world["camera"];
    if (sceneName == "crowd") {
        const double w = 2 * M_PI * t / c["period"].get<double>();
        const float x = c["center"][0].get<float>() + c["amplitude"][0].get<float>() * std::sin(c["freq"][0].get<double>() * w);
        const float y = c["center"][1].get<float>() + c["amplitude"][1].get<float>() * std::sin(c["freq"][1].get<double>() * w);
        camera->setPosition(x, y, 1);
        camera->setTarget(x, y, 0);
    } else {
        const double a = (c["start_deg"].get<double>() + c["deg_per_s"].get<double>() * t) * M_PI / 180.0;
        const float r = c["radius"], h = c["height"];
        camera->setPosition(r * std::cos(a), h, r * std::sin(a));
        camera->setTarget(v3(c["target"]));
    }
}

double unixNow() {
    return std::chrono::duration<double>(std::chrono::system_clock::now().time_since_epoch()).count();
}

void finish(double measured) {
    finished = true;
    std::cout << "BENCH_MEASURE_END" << std::endl;
    Json data = {{"engine", "Doriax"}, {"scene", sceneName}, {"objects", objects.size()},
        {"resolution", {WindowLinux::getWidth(), WindowLinux::getHeight()}},
        {"gpu", reinterpret_cast<const char*>(glGetString(GL_RENDERER))},
        {"warmup_seconds", warmup}, {"duration_seconds", measured}, {"frames", frameMs.size()},
        {"frame_ms", frameMs}, {"draw_calls", draws}, {"primitives", triangles}};
    std::ofstream file(output);
    if (!file) throw std::runtime_error("Cannot write " + output);
    file << data.dump();
    file.close();
    std::this_thread::sleep_for(std::chrono::milliseconds(200));
    System::instance().quit();
}

void tick() {
    if (finished) return;
    const auto now = Clock::now();
    if (!ready) {
        if (Engine::getQueuedResourceCount() || !scene.getSystem<RenderSystem>()->isAllLoaded()) return;
        ready = true;
        readyTime = previousTime = now;
        std::cout << "BENCH_READY " << glGetString(GL_RENDERER) << std::endl;
    }
    const double elapsed = std::chrono::duration<double>(now - readyTime).count();
    if (elapsed < warmup) {
        if (env("BENCH_CAPTURE") == "1" && elapsed > warmup / 2 && !captureSent) {
            std::cout << "BENCH_CAPTURE_WINDOW " << WindowLinux::handle() << std::endl;
            captureSent = true;
        }
        placeCamera(0);
        return;
    }
    if (!measuring) {
        measuring = true;
        measureTime = previousTime = now;
        placeCamera(0);
        std::cout << std::fixed << std::setprecision(6) << "BENCH_MEASURE_BEGIN " << unixNow() << std::endl;
        return;
    }
    frameMs.push_back(std::chrono::duration<double, std::milli>(now - previousTime).count());
    previousTime = now;
    const auto& stats = Engine::getFrameStats();
    draws.push_back(stats.drawCalls);
    triangles.push_back(stats.triangles);
    const double measured = std::chrono::duration<double>(now - measureTime).count();
    if (measured < duration) {
        placeCamera(measured);
        return;
    }
    finish(measured);
}

void buildCrowd() {
    // set up like the scene's default 2D camera (CAMERA_UI, no depth test, no transparent sort):
    // top-left origin, y down, as Godot's canvas with a top-left Camera2D
    camera = std::make_unique<Camera>(&scene);
    camera->setType(CameraType::CAMERA_UI);
    camera->setTransparentSort(false);
    camera->setDepthTest(false);
    camera->activate();
    const auto& frames = world["frames"];
    const float aw = world["atlas_size"][0], ah = world["atlas_size"][1];
    const std::string atlas = shared + "/" + world["atlas"].get<std::string>();
    for (const auto& s : world["sprites"]) {
        auto sprite = std::make_unique<Sprite>(&scene);
        sprite->setTexture(atlas);
        const auto& f = frames[s[3].get<int>()];
        sprite->setTextureRect(f[0].get<float>() / aw, f[1].get<float>() / ah, f[2].get<float>() / aw, f[3].get<float>() / ah);
        sprite->setSize(s[2].get<int>(), s[2].get<int>());
        sprite->setPivotPreset(PivotPreset::CENTER);
        sprite->setAutoTransparency(false);
        sprite->setTransparent(true);
        auto& submesh = sprite->getComponent<MeshComponent>().submeshes[0];
        submesh.material.alphaMode = MaterialAlphaMode::BLEND;
        submesh.faceCulling = false;
        sprite->setReceiveLights(false);
        sprite->setReceiveIBL(false);
        sprite->setCastShadows(false);
        sprite->setReceiveShadows(false);
        sprite->setPosition(s[0].get<float>(), s[1].get<float>(), 0);
        objects.push_back(std::move(sprite));
    }
}

void buildIsland() {
    const auto& c = world["camera"];
    camera = std::make_unique<Camera>(&scene);
    camera->setPerspective(c["yfov"].get<float>(), 1280.0f / 720.0f, c["near"].get<float>(), c["far"].get<float>());
    camera->activate();
    const auto& l = world["light"];
    light = std::make_unique<Light>(&scene);
    light->setType(LightType::DIRECTIONAL);
    light->setDirection(v3(l["direction"]));
    light->setColor(v3(l["color"]));
    light->setIntensity(l["intensity"].get<float>());
    light->setShadows(false);
    const auto& a = world["ambient"];
    scene.setGlobalIllumination(a["intensity"].get<float>(), v3(a["color"]));
    for (const auto& m : world["models"]) {
        auto model = std::make_unique<Model>(&scene);
        if (!model->loadModel(shared + "/" + m[0].get<std::string>() + ".glb")) throw std::runtime_error("Model load failed");
        model->setReceiveIBL(false);
        model->setCastShadows(false);
        model->setReceiveShadows(false);
        model->setPosition(m[1].get<float>(), m[2].get<float>(), m[3].get<float>());
        model->setRotation(yaw(m[4].get<float>()));
        model->setScale(m[5].get<float>());
        objects.push_back(std::move(model));
    }
}
}

DORIAX_INIT void init() {
    shared = env("BENCH_SHARED");
    std::ifstream input(shared + "/scenes.json");
    input >> spec;
    sceneName = env("BENCH_SCENE", "crowd");
    if (!spec.contains(sceneName)) throw std::runtime_error("Unknown scene: " + sceneName);
    world = spec[sceneName];
    warmup = std::stod(env("BENCH_WARMUP", "3"));
    duration = std::stod(env("BENCH_DURATION", "20"));
    if (!env("BENCH_FREEZE_AT").empty()) freezeAt = std::stod(env("BENCH_FREEZE_AT"));
    output = env("BENCH_OUTPUT", "/tmp/doriax-scenes.json");

    Engine::setCanvasSize(1280, 720);
    Engine::setScalingMode(Scaling::FITWIDTH);
    Engine::setScene(&scene);
    const auto& bg = world["background"];
    scene.setBackgroundColor(bg[0], bg[1], bg[2], bg[3]);
    scene.setLightState(sceneName == "island" ? LightState::ON : LightState::OFF);
    scene.setMeshLodEnabled(false);
    scene.setDepthPrepassEnabled(false);
    scene.setSSAOEnabled(false);
    scene.setSSREnabled(false);

    if (sceneName == "crowd") buildCrowd(); else buildIsland();
    placeCamera(0);
    Engine::onUpdate.add("bench", &tick);
}
