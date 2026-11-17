#include "Bench.h"

#include "BundleManager.h"
#include "Object.h"

#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <ctime>
#include <functional>
#include <thread>

using namespace doriax;

namespace {
    std::string env(const char* name, const std::string& fallback) {
        const char* value = std::getenv(name);
        return value ? value : fallback;
    }

    // CPU time of this thread: time other programs take from the core is not counted
    double threadMs() {
        timespec ts;
        clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts);
        return ts.tv_sec * 1000.0 + ts.tv_nsec / 1000000.0;
    }

    int envInt(const char* name, int fallback) {
        const char* value = std::getenv(name);
        return value ? std::atoi(value) : fallback;
    }

    // a bundle instance holds its entities under a root of its own; scripts move the member
    Entity spawnMember(Scene* scene, const std::string& bundle, const std::string& member) {
        Entity root = BundleManager::createBundle(bundle, scene);
        Entity entity = scene->findEntity(member, root);
        return entity != NULL_ENTITY ? entity : root;
    }

    // xorshift32, so every run places its objects the same way
    uint32_t seed = 1234;
    uint32_t random(uint32_t n) {
        seed ^= seed << 13;
        seed ^= seed >> 17;
        seed ^= seed << 5;
        return seed % n;
    }
}

Bench::Bench(Scene* scene, Entity entity): ScriptBase(scene, entity) {
    REGISTER_ENGINE_EVENT(onUpdate);
}

Bench::~Bench() {
    UNREGISTER_ENGINE_EVENT(onUpdate);
    if (!endTag.empty()) {
        Engine::onUpdate.remove(endTag);
    }
}

void Bench::spawn() {
    lang = env("BENCH_LANG", "cpp");
    count = envInt("BENCH_COUNT", count);
    warmup = envInt("BENCH_WARMUP", warmup);
    frames = envInt("BENCH_FRAMES", frames);
    stepFps = envInt("BENCH_STEP", 0);
    output = env("BENCH_OUT", "");

    std::string suffix = lang == "lua" ? "Lua" : (lang == "off" ? "Off" : "Cpp");
    Scene* scene = getScene();

    if (round == 1) {
        spawnMember(scene, "assets/arena/Player_" + suffix, "Player");
        for (int i = 0; i < count; i++) {
            float angle = random(3600) * 0.1f * 3.14159265f / 180.0f;
            float radius = 14.0f + random(80) * 0.1f;
            Object enemy(scene, spawnMember(scene, "assets/arena/Enemy_" + suffix, "Enemy"));
            enemy.setPosition(std::cos(angle) * radius, 0.5f, std::sin(angle) * radius);
            enemy.setScale(0.8f);
        }
    } else if (round == 2) {
        int side = (int)std::ceil(std::sqrt((float)count));
        for (int i = 0; i < count; i++) {
            Object cube(scene, spawnMember(scene, "assets/crowd/Cube_" + suffix, "Cube"));
            cube.setPosition((i % side - side * 0.5f) * 1.25f, 0.0f, (i / side - side * 0.5f) * 1.25f);
        }
    } else if (round == 3) {
        BundleManager::createBundle("assets/paths/Paths_" + suffix, scene);
    } else if (round == 4) {
        BundleManager::createBundle("assets/rays/Rays_" + suffix, scene);
    }

    // added after the scripts above, so it runs after all of them
    endTag = "BenchScriptsDone" + std::to_string((uintptr_t)this);
    Engine::onUpdate.add(endTag, std::function<void()>([this]() { scriptsDone(); }));

    printf("BENCH_SPAWNED round %d lang %s count %d\n", round, lang.c_str(), count);
    fflush(stdout);
}

void Bench::scriptsDone() {
    if (stepFps > 0 || frame <= warmup) return;
    auto now = std::chrono::steady_clock::now();
    scriptTimes.push_back(std::chrono::duration<float, std::milli>(now - scriptsStart).count());
    scriptCpu.push_back(threadMs() - scriptsStartCpu);
}

void Bench::onUpdate() {
    auto now = std::chrono::steady_clock::now();
    if (!spawned) {
        spawn();
        spawned = true;
        last = now;
        return;
    }

    if (stepFps > 0) {
        // recording: every frame lasts at least 1/fps and moves the game 1/fps
        Engine::setMaxDeltatime(1.0f / stepFps);
        auto length = std::chrono::duration_cast<std::chrono::steady_clock::duration>(
            std::chrono::duration<double>(1.0 / stepFps + 0.003));
        std::this_thread::sleep_until(last + length);
        last = std::chrono::steady_clock::now();
        printf("BENCH_STEP_FRAME %d\n", ++frame);
        fflush(stdout);
        return;
    }

    float ms = std::chrono::duration<float, std::milli>(now - last).count();
    double cpu = threadMs();
    float cpuMs = cpu - lastCpu;
    last = now;
    lastCpu = cpu;
    frame++;
    if (frame == warmup) {
        printf("BENCH_MEASURE_BEGIN\n");
        fflush(stdout);
    }
    if (frame > warmup) {
        times.push_back(ms);
        frameCpu.push_back(cpuMs);
        if (frames > 0 && (int)times.size() >= frames) {
            finish();
        }
    }
    scriptsStart = std::chrono::steady_clock::now();
    scriptsStartCpu = threadMs();
}

void Bench::finish() {
    printf("BENCH_MEASURE_END\n");
    if (!output.empty()) {
        if (FILE* f = fopen(output.c_str(), "w")) {
            fprintf(f, "{\"round\": %d, \"lang\": \"%s\", \"count\": %d, \"frames\": [", round, lang.c_str(), count);
            for (size_t i = 0; i < times.size(); i++) {
                fprintf(f, "%s%.4f", i ? ", " : "", times[i]);
            }
            fprintf(f, "], \"scripts\": [");
            for (size_t i = 0; i < scriptTimes.size(); i++) {
                fprintf(f, "%s%.4f", i ? ", " : "", scriptTimes[i]);
            }
            fprintf(f, "], \"framesCpu\": [");
            for (size_t i = 0; i < frameCpu.size(); i++) {
                fprintf(f, "%s%.4f", i ? ", " : "", frameCpu[i]);
            }
            fprintf(f, "], \"scriptsCpu\": [");
            for (size_t i = 0; i < scriptCpu.size(); i++) {
                fprintf(f, "%s%.4f", i ? ", " : "", scriptCpu[i]);
            }
            fprintf(f, "]}\n");
            fclose(f);
        }
    }
    fflush(stdout);
    std::_Exit(0);
}
