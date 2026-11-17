#include "Rays.h"

#include "BundleManager.h"
#include "Object.h"
#include "Ray.h"

#include <cmath>

using namespace doriax;

namespace {
    const double STEP = 1.0 / 60.0; // fixed step, so every run casts the same rays
    const double RANGE = 40.0;
    const double TO_RAD = 3.14159265358979323846 / 180.0;
}

Rays::Rays(Scene* scene, Entity entity): ScriptBase(scene, entity) {
    REGISTER_ENGINE_EVENT(onUpdate);
}

Rays::~Rays() {
    UNREGISTER_ENGINE_EVENT(onUpdate);
}

// xorshift32, the same numbers as the Lua version
uint32_t Rays::random(uint32_t n) {
    seed ^= seed << 13;
    seed ^= seed >> 17;
    seed ^= seed << 5;
    return seed % n;
}

void Rays::build() {
    Scene* scene = getScene();
    for (int i = 0; i < 160; i++) {
        double angle = random(3600) / 10.0 * TO_RAD;
        double radius = 6 + random(320) / 10.0;
        // the body is on the bundle's member, so that is the entity to place
        Entity root = BundleManager::createBundle("assets/rays/Pillar", scene);
        Object pillar(scene, scene->findEntity("Pillar", root));
        pillar.setPosition(std::cos(angle) * radius, 2.0f, std::sin(angle) * radius);
        pillar.setRotation(0.0f, (float)random(360), 0.0f);
        pillar.setScale(Vector3(1.2f, 4.0f, 1.2f));
    }

    points = std::make_unique<Points>(scene);
    points->setMaxPoints(rayCount);
    for (int i = 0; i < rayCount; i++) {
        points->addPoint(Vector3(0, -100, 0), Vector4(0.35f, 1.0f, 0.75f, 1.0f), 0.4f);
    }
}

void Rays::onUpdate() {
    if (!points) {
        build();
    }
    if (!simulate) return;

    sweep += 40.0 * STEP;
    Scene* scene = getScene();
    Vector3 origin(0.0f, 1.5f, 0.0f);
    for (int i = 0; i < rayCount; i++) {
        double a = (i * 360.0 / rayCount + sweep) * TO_RAD;
        double tilt = std::sin(i * 0.37 + sweep * 0.1) * 3.0 * TO_RAD;
        double c = std::cos(tilt);
        Vector3 dir(std::cos(a) * c * RANGE, std::sin(tilt) * RANGE, std::sin(a) * c * RANGE);
        RayReturn hit = Ray(origin, dir).intersects(scene, RayFilter::BODY_3D);
        if (hit.hit) {
            points->updatePoint(i, hit.point);
        } else {
            points->updatePoint(i, origin + dir);
        }
    }
}
