// The twelve stress tests; mirrors godot/main.gd. Time spent moving objects is measured separately.
#include "Doriax.h"
#include "WindowLinux.h"
#include "json.hpp"
#include <GL/gl.h>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <memory>
#include <set>
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
Json spec, workload;
std::vector<std::unique_ptr<Object>> objects;
std::vector<Vector3> bases;
std::vector<float> phases;
std::vector<double> frameMs, scriptMs;
std::vector<unsigned int> draws;
std::vector<uint64_t> triangles;
Quaternion baseRotation;
Clock::time_point readyTime, previousTime, measureTime;
bool ready = false, measuring = false, finished = false, captureSent = false, freeze = false;
double warmup, duration, scriptAccum = 0;
std::string output, shared;

std::string env(const char* name, const std::string& fallback = "") {
    const char* value = std::getenv(name);
    return value ? value : fallback;
}
Vector3 v3(const Json& p) { return Vector3(p[0].get<float>(), p[1].get<float>(), p[2].get<float>()); }

Quaternion spin(float angle) {
    return baseRotation * Quaternion(std::cos(angle * 0.5f), 0, std::sin(angle * 0.5f), 0);
}

void move(double t) {
    if (!workload["moving"].get<bool>()) return;
    const auto start = Clock::now();
    const auto& m = spec["motion"];
    const float speed = m["angular_speed"], ax = m["x_amplitude"], ay = m["y_amplitude"];
    if (workload["kind"] == "sprites") {
        for (size_t i = 0; i < objects.size(); ++i)
            objects[i]->setPosition(bases[i].x + ax * std::sin(speed * t + phases[i]),
                                    bases[i].y + ay * std::cos(speed * t + phases[i]), 0);
    } else {
        for (size_t i = 0; i < objects.size(); ++i)
            objects[i]->setRotation(spin(speed * t + phases[i]));
    }
    scriptAccum += std::chrono::duration<double, std::milli>(Clock::now() - start).count();
}

Json positions() {
    Json result = Json::array();
    for (auto& object : objects) {
        const Vector3 p = object->getPosition();
        result.push_back({p.x, p.y, p.z});
    }
    return result;
}

Json rotations() {
    Json result = Json::array();
    for (size_t i : {size_t(0), objects.size() / 2, objects.size() - 1}) {
        const Quaternion q = objects[i]->getRotation();
        result.push_back({q.x, q.y, q.z, q.w});
    }
    return result;
}

Json resources() {
    Json result = {{"msaa", System::instance().getSampleCount()}, {"depth_prepass", scene.isDepthPrepassEnabled()},
                   {"ssao", scene.isSSAOEnabled()}, {"ssr", scene.isSSREnabled()}, {"objects", objects.size()}};
    std::set<std::string> textures;
    bool blend = true, culling = false, shadows = false, unlit = true;
    for (auto& object : objects) {
        auto& mesh = object->getComponent<MeshComponent>();
        for (unsigned int s = 0; s < mesh.numSubmeshes; s++) {
            const auto& submesh = mesh.submeshes[s];
            blend &= submesh.alphaBlend;
            culling |= submesh.faceCulling;
            unlit &= (submesh.shaderProperties & 1u) != 0;
            if (!submesh.material.baseColorTexture.empty()) textures.insert(submesh.material.baseColorTexture.getId());
        }
        shadows |= mesh.castShadows || mesh.receiveShadows;
    }
    result["alpha_blend"] = blend;
    result["face_culling"] = culling;
    result["shadows"] = shadows;
    result["unlit"] = unlit;
    result["textures"] = textures.size();
    return result;
}

void finish(double measured) {
    finished = true;
    std::cout << "BENCH_MEASURE_END" << std::endl;
    const size_t count = workload["instanced"].get<bool>() ? objects[0]->getComponent<InstancedMeshComponent>().instances.size() : objects.size();
    if (count != workload["count"].get<size_t>()) throw std::runtime_error("Object count mismatch");
    Json data = {{"engine", "Doriax"}, {"case", workload["id"]}, {"count", count},
        {"resolution", {WindowLinux::getWidth(), WindowLinux::getHeight()}},
        {"gpu", reinterpret_cast<const char*>(glGetString(GL_RENDERER))},
        {"warmup_seconds", warmup}, {"duration_seconds", measured}, {"frames", frameMs.size()},
        {"frame_ms", frameMs}, {"script_ms", scriptMs}, {"draw_calls", draws}, {"primitives", triangles}};
    move(0); data["positions_t0"] = positions(); data["rotations_t0"] = rotations();
    move(1); data["positions_t1"] = positions(); data["rotations_t1"] = rotations();
    data["resources"] = resources();
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
        move(freeze ? 0 : elapsed);
        return;
    }
    if (!measuring) {
        measuring = true;
        measureTime = previousTime = now;
        scriptAccum = 0;
        move(0);
        std::cout << "BENCH_MEASURE_BEGIN" << std::endl;
        return;
    }
    frameMs.push_back(std::chrono::duration<double, std::milli>(now - previousTime).count());
    scriptMs.push_back(scriptAccum);
    scriptAccum = 0;
    previousTime = now;
    const auto& stats = Engine::getFrameStats();
    draws.push_back(stats.drawCalls);
    triangles.push_back(stats.triangles);
    const double measured = std::chrono::duration<double>(now - measureTime).count();
    if (measured < duration) {
        move(freeze ? 0 : measured);
        return;
    }
    finish(measured);
}

void setupCamera() {
    const auto& settings = spec["camera"];
    camera = std::make_unique<Camera>(&scene);
    camera->setAutoResize(false);
    camera->setPosition(v3(settings["position"]));
    camera->setTarget(v3(settings["target"]));
    const float halfH = settings["ortho_height"].get<float>() / 2, halfW = halfH * 1280 / 720;
    camera->setOrtho(-halfW, halfW, -halfH, halfH, settings["near"], settings["far"]);
    camera->activate();
}

void setupLight() {
    const auto& settings = spec["light"];
    light = std::make_unique<Light>(&scene);
    light->setType(LightType::DIRECTIONAL);
    light->setDirection(v3(settings["direction"]));
    light->setColor(v3(settings["color"]));
    light->setIntensity(settings["energy"].get<float>());
    light->setShadows(false);
}
}

DORIAX_INIT void init() {
    shared = env("BENCH_SHARED");
    std::ifstream input(shared + "/workloads.json");
    input >> spec;
    const auto selected = env("BENCH_CASE", "sprites_static_3000");
    for (const auto& item : spec["cases"]) if (item["id"] == selected) workload = item;
    if (workload.is_null()) throw std::runtime_error("Unknown case: " + selected);
    warmup = std::stod(env("BENCH_WARMUP", "3"));
    duration = std::stod(env("BENCH_DURATION", "8"));
    freeze = env("BENCH_FREEZE") == "1";
    output = env("BENCH_OUTPUT", "/tmp/doriax-bench.json");

    Engine::setCanvasSize(1280, 720);
    Engine::setScalingMode(Scaling::FITWIDTH);
    Engine::setScene(&scene);
    const auto& bg = spec["background"];
    scene.setBackgroundColor(bg[0], bg[1], bg[2], bg[3]);
    scene.setLightState(workload["lit"].get<bool>() ? LightState::ON : LightState::OFF);
    scene.setMeshLodEnabled(false);
    scene.setDepthPrepassEnabled(false);
    scene.setSSAOEnabled(false);
    scene.setSSREnabled(false);

    const int count = workload["count"];
    const auto& q = spec["cube_rotation"];
    baseRotation = Quaternion(q[3].get<float>(), q[0].get<float>(), q[1].get<float>(), q[2].get<float>());

    if (workload["kind"] == "sprites") {
        // CAMERA_UI uses the same top-left, y-down coordinates as Godot's canvas.
        const int textures = workload["textures"];
        for (int i = 0; i < count; ++i) {
            auto sprite = std::make_unique<Sprite>(&scene);
            sprite->setTexture(shared + "/sprite" + std::to_string(i % textures) + ".png");
            sprite->setSize(16, 16);
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
            const auto& p = spec["sprites"][i];
            bases.emplace_back(p[0].get<float>(), p[1].get<float>(), 0);
            phases.push_back(p[2]);
            sprite->setPosition(bases.back());
            objects.push_back(std::move(sprite));
        }
    } else {
        setupCamera();
        if (workload["lit"].get<bool>()) setupLight();
        const bool lit = workload["lit"], instanced = workload["instanced"];
        const auto& color = spec["cube_color"];
        for (int i = 0; i < (instanced ? 1 : count); ++i) {
            const auto& p = spec["cubes"][i];
            if (workload["kind"] == "models") {
                auto model = std::make_unique<Model>(&scene);
                if (!model->loadModel(shared + "/key.glb")) throw std::runtime_error("Model load failed");
                model->setReceiveIBL(false);
                model->setCastShadows(false);
                model->setReceiveShadows(false);
                model->setScale(spec["model_scale"].get<float>());
                objects.push_back(std::move(model));
            } else {
                auto cube = std::make_unique<Shape>(&scene);
                cube->createBox(1, 1, 1);
                cube->setColor(color[0], color[1], color[2], color[3]);
                cube->setReceiveLights(lit);
                cube->setReceiveIBL(false);
                cube->setCastShadows(false);
                cube->setReceiveShadows(false);
                if (lit) {
                    auto& material = cube->getComponent<MeshComponent>().submeshes[0].material;
                    material.metallicFactor = 0;
                    material.roughnessFactor = 1;
                }
                if (instanced) {
                    cube->createInstancedMesh();
                    cube->setMaxInstances(count);
                    cube->setCullInstances(false);
                    for (int j = 0; j < count; ++j)
                        cube->addInstance(v3(spec["cubes"][j]), baseRotation, Vector3(1, 1, 1));
                }
                objects.push_back(std::move(cube));
            }
            if (!instanced) {
                objects.back()->setPosition(v3(p));
                objects.back()->setRotation(baseRotation);
                bases.push_back(v3(p));
                phases.push_back(p[3]);
            }
        }
    }
    move(0);
    Engine::onUpdate.add("bench", &tick);
}
