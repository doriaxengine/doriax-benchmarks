// Benchmark driver for Lost Slime 3D, added to an exported copy of the game (see build.sh).
// It loads a level and flies the camera along benchmark/routes.json, like scripts/benchmark.gd in the port.
#include "Engine.h"
#include "SceneManager.h"
#include "Camera.h"
#include "Object.h"
#include "GameState.h"
#include "WindowLinux.h"
#include <GL/gl.h>
#include <GL/glx.h>
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>
#include <unistd.h>
#include "json.hpp"

namespace {
using namespace doriax;
using Clock = std::chrono::steady_clock;
using Json = nlohmann::json;
std::string level, output, screenshot;
double warmup = 5.0, duration = 20.0;
bool requested = false, ready = false, measured = false, done = false, captured = false;
Clock::time_point startTime, previousTime, measureTime;
Json frames = Json::array(), draws = Json::array(), triangles = Json::array();
std::vector<Vector3> route;

std::string env(const char* name, const std::string& fallback = "") {
    const char* value = std::getenv(name);
    return value ? value : fallback;
}

void capture() {
    // XWayland does not expose the presented front buffer through glReadPixels.
    // Ask the outer runner to capture this specific game window during warmup.
    std::cout << "BENCH_CAPTURE_WINDOW " << WindowLinux::handle() << std::endl;
}

void tick() {
    if (done) return;
    if (!requested) {
        if (!SceneManager::isLoading()) {
            requested = true;
            SceneManager::loadScene(level);
        }
        return;
    }
    if (SceneManager::isLoading() || GameState::lastLevelScene != level) return;
    Scene* scene = Engine::getMainScene();
    if (!scene || scene->getCamera() == NULL_ENTITY) return;
    const auto now = Clock::now();
    if (!ready) {
        ready = true;
        startTime = previousTime = now;
        std::cout << "BENCH_READY " << getpid() << " " << glGetString(GL_RENDERER) << " " << level << std::endl;
    }
    double elapsed = std::chrono::duration<double>(now - startTime).count();
    double u = std::clamp(elapsed >= warmup ? (elapsed - warmup) / duration : elapsed / warmup, 0.0, 1.0);
    double segment = u * (route.size() - 1);
    size_t index = std::min(static_cast<size_t>(segment), route.size() - 2);
    Vector3 focus = route[index] + (route[index + 1] - route[index]) * static_cast<float>(segment - index);
    constexpr double pi = 3.14159265358979323846;
    double yaw = (-90.0 + 25.0 * std::sin(u * 2.0 * pi)) * pi / 180.0;
    double pitch = -22.0 * pi / 180.0;
    Vector3 forward(-std::sin(yaw) * std::cos(pitch), std::sin(pitch), -std::cos(yaw) * std::cos(pitch));
    Vector3 target = focus + Vector3(0, 1, 0);
    Camera camera(scene, scene->getCamera());
    camera.setPosition(target - forward * 9.0f);
    camera.setTarget(target);
    if (elapsed < warmup) {
        if (!screenshot.empty() && !captured && u > 0.5) {
            capture();
            captured = true;
        }
        previousTime = now;
        return;
    }
    if (!measured) {
        measured = true;
        measureTime = previousTime = now;
        std::cout << "BENCH_MEASURE_BEGIN" << std::endl;
        return;
    }
    frames.push_back(std::chrono::duration<double, std::milli>(now - previousTime).count());
    previousTime = now;
    const auto& stats = Engine::getFrameStats();
    draws.push_back(stats.drawCalls);
    triangles.push_back(stats.triangles);
    if (elapsed >= warmup + duration) {
        done = true;
        Json report = {{"engine", "Doriax"}, {"scene", level}, {"resolution", {1280,720}},
            {"gpu", reinterpret_cast<const char*>(glGetString(GL_RENDERER))}, {"renderer", "OpenGL"},
            {"warmup_seconds", warmup}, {"duration_seconds", std::chrono::duration<double>(now - measureTime).count()},
            {"frames", frames.size()}, {"frame_ms", frames}, {"draw_calls", draws}, {"primitives", triangles},
            {"build_type", "Release"}};
        std::ofstream file(output);
        file << report.dump();
        file.close();
        std::cout << "BENCH_MEASURE_END " << frames.size() << " frames" << std::endl;
        System::instance().quit();
    }
}

struct Register {
    Register() {
        Engine::getOnInit().add("lostslime_benchmark", []() {
            level = env("LOSTSLIME_BENCH_LEVEL");
            if (level.empty()) return;
            output = env("LOSTSLIME_BENCH_OUTPUT", "/tmp/doriax-benchmark.json");
            screenshot = env("LOSTSLIME_BENCH_SCREENSHOT");
            duration = std::stod(env("LOSTSLIME_BENCH_DURATION", "20"));
            warmup = std::stod(env("LOSTSLIME_BENCH_WARMUP", "5"));
            std::ifstream file(env("LOSTSLIME_BENCH_ROUTES"));
            Json routes; file >> routes;
            for (const auto& p : routes.at(level)) route.emplace_back(p[0].get<float>(), p[1].get<float>(), p[2].get<float>());
            // Register after the level's PlayerController subscribes. Camera
            // overrides must precede Scene::update(), which computes view matrices.
            Engine::onDraw.add("lostslime_benchmark_wait", []() {
                static bool subscribed = false;
                if (subscribed) return;
                if (!requested) {
                    if (!SceneManager::isLoading()) {
                        requested = true;
                        SceneManager::loadScene(level);
                    }
                    return;
                }
                if (!SceneManager::isLoading() && GameState::lastLevelScene == level) {
                    Engine::onUpdate.add("lostslime_benchmark_frame", &tick);
                    subscribed = true;
                }
            });
        });
    }
} registration;
}
