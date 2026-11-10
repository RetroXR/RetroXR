// VerletRope — the per-tick simulation. Split from VerletRope.cpp, which holds
// the bindings and lifecycle, purely to keep both files readable.
//
// Ported from verlet_rope.gd. Constraint order, contact caching and sleep rules
// all match it; where the GDScript had constraints hand-inlined into the solver
// loop to dodge interpreter call overhead, they are ordinary inline functions
// again here.

#include <godot_cpp/variant/utility_functions.hpp>
#include <cstdlib>
#include "VerletRope.hpp"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/physics_direct_space_state3d.hpp>
#include <godot_cpp/classes/world3d.hpp>

#include <algorithm>
#include <cmath>
#include <functional>
#include <limits>
#include <queue>

using namespace godot;

namespace Xenu
{

namespace
{
constexpr int SLEEP_FRAMES = 45;
constexpr double SLEEP_MAX_VELOCITY_EPS_SQ = 0.0025 * 0.0025;
constexpr double SLEEP_RMS_VELOCITY_EPS_SQ = 0.0004 * 0.0004;
// These are sanity gates, not equilibrium tolerances: a deliberately heaped
// cord begins extremely compressed and can retain large local constraint error
// while being perfectly motionless. Velocity decides rest; residuals only stop
// a pathological/tunnelled solve from being frozen and hidden.
constexpr double SLEEP_STRETCH_ERROR = 4.0;
constexpr double SLEEP_CONTACT_ERROR = 0.05;
// How long a cord may hold a segment past SLEEP_STRETCH_ERROR with its ends
// still before it is laid afresh (see UpdateSleepState).
constexpr int HOPELESS_FRAMES = 180;
constexpr double WAKE_ANCHOR_EPS_SQ = 0.0005 * 0.0005;
// A sleeping rope has no CollisionObject3D of its own, so furniture cannot wake
// it through a physics callback. Poll its cached contacts at a low cadence:
// three times a second at the project's 90 Hz tick catches moved support
// without turning every sleeping cable back into a per-frame physics cost.
// A poll is one shape query per segment and one point query per particle,
// and with eight sleeping cables in a room the 15-tick cadence was 3% of a
// Quest 3's main thread; two polls have to agree before a wake, so the worst
// case from a removed support to the cord falling is 60 ticks.
constexpr int SLEEP_ENVIRONMENT_INTERVAL = 30;
// Further than an anchor can travel in one tick by being carried or thrown: 0.4 m
// at 60 Hz is 24 m/s, where a hard throw is nearer 10. Every teleport a restore
// performs is 0.7 m or more, so the gap is wide. See AnchorTeleported.
constexpr double TELEPORT_EPS_SQ = 0.4 * 0.4;
// Most the cord may change a loose plug's velocity in one step, through
// CouplePlug's force and torque. The coupling is physical — a few grams of cord
// against a plug of tens of grams — and never reaches these in normal handling;
// they are there for a whipping cord, whose corrections are no longer small.
// A force goes through the physics server's own solver, so unlike the old
// aligning teleport it cannot carry a plug through a floor, but a light plug
// spun at hundreds of rad/s still reads as a glitch.
constexpr double MAX_COUPLE_DV = 0.5;
constexpr double MAX_COUPLE_DW = 12.0;
} // namespace

// ── Constraint primitives ───────────────────────────────────────────────────

// Positional constraint between points a/b toward rest distance, split by
// inverse mass.
inline void VerletRope::SolvePair(int a, int b, double rest, double k, double *lambda)
{
    const float w_a = m_inv_mass[a];
    const float w_b = m_inv_mass[b];
    const float w_sum = w_a + w_b;
    if (w_sum == 0.0f)
        return;
    const Vector3 diff = m_points[b] - m_points[a];
    const double dist = diff.length();
    if (dist < 0.0001)
        return;
    if (lambda == nullptr || m_stretch_compliance <= 0.0)
    {
        // Keep the authored-stiffness path arithmetically identical to the
        // pre-XPBD solver. Settling is chaotic enough that even reassociating
        // these multiplies changes a pose several metres down a translated test.
        const Vector3 correction = diff * ((dist - rest) / dist) * k;
        m_points[a] += correction * (w_a / w_sum);
        m_points[b] -= correction * (w_b / w_sum);
        if (w_a == 0.0f || w_b == 0.0f)
            AddPinReaction(w_a == 0.0f ? a : b, w_a == 0.0f ? correction : -correction,
                           Vector3());
        return;
    }
    const double alpha = m_stretch_compliance / m_step_dt_sq;
    const double c = dist - rest;
    const double delta_lambda = (-c - alpha * *lambda) / (w_sum + alpha);
    *lambda += delta_lambda;
    const Vector3 correction = diff * (-delta_lambda / dist);
    m_points[a] += correction * (w_a / w_sum);
    m_points[b] -= correction * (w_b / w_sum);
    if (w_a == 0.0f || w_b == 0.0f)
        AddPinReaction(w_a == 0.0f ? a : b, w_a == 0.0f ? correction : -correction, Vector3());
}

// Which pin slot a pinned particle is: 0 the trunk's start, 1 its end, 2+g the
// end of fray chain g, or -1. Only asked about particles with zero inverse
// mass, which is what keeps it off the hot path.
int VerletRope::PinSlot(int p_particle) const
{
    if (p_particle == 0)
        return 0;
    if (p_particle == TrunkCount() - 1)
        return 1;
    for (size_t g = 0; g < m_fray.size(); ++g)
        if (p_particle == m_fray[g].first + m_fray[g].count - 1)
            return 2 + static_cast<int>(g);
    return -1;
}

// Record that a constraint moved a free particle by -p_push against pinned
// particle p_pinned: had the pin been free, it would have taken p_push. p_arm
// is where that push acts, relative to the pin — zero for a segment, which
// pulls straight on the pin; the boot's pushes act out along the cord.
inline void VerletRope::AddPinReaction(int p_pinned, const Vector3 &p_push, const Vector3 &p_arm)
{
    const int slot = PinSlot(p_pinned);
    if (slot < 0 || slot >= static_cast<int>(m_pin_push.size()))
        return;
    m_pin_push[slot] += p_push;
    m_pin_moment[slot] += p_arm.cross(p_push);
}

// Angular bend constraint: pull particle b toward the midpoint of its
// neighbours at +/-spacing (momentum-balanced), ignoring deviation below
// allowed_dev.
inline void VerletRope::SolveBend(int b, int spacing, double allowed_dev, double k)
{
    SolveBendTriple(b - spacing, b, b + spacing, allowed_dev, k);
}

// The same constraint over three arbitrary particles. A branch's link back to
// the trunk is not evenly spaced in the array — the junction's neighbours are
// the trunk's last particle and a branch's first, which live nowhere near each
// other — so the spacing form above cannot express it.
inline void VerletRope::SolveBendTriple(int a, int b, int c, double allowed_dev, double k)
{
    const float w_a = m_inv_mass[a];
    const float w_b = m_inv_mass[b];
    const float w_c = m_inv_mass[c];
    const float w_total = w_b + 0.5f * (w_a + w_c);
    if (w_total == 0.0f)
        return;
    const Vector3 delta = (m_points[a] + m_points[c]) * 0.5f - m_points[b];
    const double dev_sq = delta.length_squared();
    // The degenerate case has to be dropped rather than scaled: nudging an
    // already-straight triple by a fraction of a micrometre is what used to stop
    // a settled rope going to sleep.
    if (dev_sq < 1e-8)
        return;
    const double dev = std::sqrt(dev_sq);
    if (allowed_dev > 0.0 && dev <= allowed_dev)
        return;

    Vector3 v;
    if (allowed_dev > 0.0)
    {
        v = delta * ((dev - allowed_dev) / dev * k);
    }
    else
    {
        // No free-bend allowance makes the (dev - allowed) / dev scale exactly
        // 1, so the correction is delta * k and the length is never needed. This
        // is the default path: max_bend_degrees is 0 unless a rope opts in, and
        // the strain-relief stub always passes 0.
        v = delta * k;
    }
    if (m_bend_compliance > 0.0)
    {
        const double alpha = m_bend_compliance / m_step_dt_sq;
        Vector3 &lambda = m_bend_lambda[BendLambdaKey(a, b, c, false, allowed_dev, k)];
        const Vector3 delta_lambda = (v / k - lambda * alpha) / (w_total + alpha);
        lambda += delta_lambda;
        m_points[b] += delta_lambda * w_b;
        m_points[a] -= delta_lambda * (0.5f * w_a);
        m_points[c] -= delta_lambda * (0.5f * w_c);
    }
    else
    {
        m_points[b] += v * (w_b / w_total);
        m_points[a] -= v * (0.5f * w_a / w_total);
        m_points[c] -= v * (0.5f * w_c / w_total);
    }
}

// True local angular bending. Stiffness controls the correction toward the free
// angle, resistance ramps progressively near a fold, and the hard limit handles
// adjacent segments that self-collision deliberately excludes.
inline void VerletRope::SolveAngleBend(int a, int b, int c, double free_angle, double k)
{
    const Vector3 incoming = m_points[b] - m_points[a];
    const Vector3 outgoing = m_points[c] - m_points[b];
    const double incoming_len = incoming.length();
    const double outgoing_len = outgoing.length();
    if (incoming_len < 1e-6 || outgoing_len < 1e-6)
        return;
    const Vector3 u = incoming / incoming_len;
    const Vector3 v_out = outgoing / outgoing_len;
    const double forward_dot = CLAMP(u.dot(v_out), -1.0, 1.0);
    const double turn = std::acos(forward_dot);
    const double stiffen = Math::deg_to_rad(CLAMP(m_bend_stiffen_degrees, 0.0, 180.0));
    const double limit = Math::deg_to_rad(
        CLAMP(std::max(m_bend_limit_degrees, m_bend_stiffen_degrees + 0.001), 0.0, 180.0));
    if (turn <= stiffen)
        return;

    double k_eff = CLAMP(k, 0.0, 1.0);
    double target_turn;
    if (turn > limit)
        target_turn = limit;
    else
    {
        const double t = turn > stiffen
                             ? CLAMP((turn - stiffen) / (limit - stiffen), 0.0, 1.0)
                             : 0.0;
        const double ramp = t * t * (3.0 - 2.0 * t);
        // Multiply the authored response progressively rather than blending
        // toward rigidity. A soft cable remains softer than a stiff one even
        // near the limit; only the separate hard-limit branch is absolute.
        k_eff = 1.0 - std::pow(1.0 - k_eff, 1.0 + ramp * 12.0);
        target_turn = turn - (turn - stiffen) * k_eff;
    }
    const Vector3 reference = std::abs(u.dot(Vector3(0, 1, 0))) < 0.9
                                  ? Vector3(0, 1, 0)
                                  : Vector3(1, 0, 0);
    const Vector3 stable_axis = u.cross(reference).normalized();
    Vector3 axis = u.cross(v_out);
    if (axis.length_squared() < 1e-10)
        axis = stable_axis;
    else
    {
        axis.normalize();
        if (axis.dot(stable_axis) < 0.0)
            axis = -axis;
    }
    const double sin_turn = std::sqrt(std::max(0.0, 1.0 - forward_dot * forward_dot));
    const float w_b = m_inv_mass[b];
    const float w_c = m_inv_mass[c];
    const float w_a = m_inv_mass[a];

    // At an exact hairpin the angle gradient is undefined. One deterministic
    // angular projection breaks the symmetry; subsequent iterations use the
    // regular three-particle gradient below.
    if (sin_turn < 1e-5)
    {
        const Vector3 target = Basis(axis, target_turn).xform(u) * outgoing_len;
        const Vector3 correction = target - outgoing;
        const float w_sum = w_b + w_c;
        if (w_sum > 0.0f)
        {
            m_points[b] -= correction * (w_b / w_sum);
            m_points[c] += correction * (w_c / w_sum);
        }
        return;
    }

    const Vector3 g_a = (v_out - u * forward_dot) / (incoming_len * sin_turn);
    const Vector3 g_c = -(u - v_out * forward_dot) / (outgoing_len * sin_turn);
    const Vector3 g_b = -g_a - g_c;
    const double weight = w_a * g_a.length_squared() +
                          w_b * g_b.length_squared() +
                          w_c * g_c.length_squared();
    if (weight < 1e-10)
        return;

    // Angle gradients preserve segment lengths only to first order. Bound a
    // nonlinear correction so one iteration cannot manufacture stretch while
    // trying to open a severe fold; repeated solver iterations converge it.
    const double constraint = std::min(turn - target_turn, Math::deg_to_rad(5.0));
    const uint64_t key = BendLambdaKey(a, b, c, false, free_angle, k);
    double &lambda = m_angle_lambda[key];
    const double alpha = m_bend_compliance > 0.0 ? m_bend_compliance / m_step_dt_sq : 0.0;
    const double delta_lambda = (-constraint - alpha * lambda) / (weight + alpha);
    lambda += delta_lambda;
    m_points[a] += g_a * (w_a * delta_lambda);
    m_points[b] += g_b * (w_b * delta_lambda);
    m_points[c] += g_c * (w_c * delta_lambda);
}

// Bend on (a, b, c) with `a` held immovable — the correction is shared by b and c
// only.
//
// For a junction: it is one particle shared by the trunk and every branch, and
// letting each branch push it turns a three-way fray into a tug of war. Each
// branch straightening its own first particle is wanted; three of them elbowing
// the breakout every iteration is what stopped a lead ever settling on a table.
inline void VerletRope::SolveBendAnchored(int a, int b, int c, double k)
{
    const float w_b = m_inv_mass[b];
    const float w_c = m_inv_mass[c];
    const float w_total = w_b + 0.5f * w_c;
    if (w_total == 0.0f)
        return;
    const Vector3 delta = (m_points[a] + m_points[c]) * 0.5f - m_points[b];
    if (delta.length_squared() < 1e-8)
        return;
    const Vector3 v = delta * k;
    if (m_bend_compliance > 0.0)
    {
        const double alpha = m_bend_compliance / m_step_dt_sq;
        Vector3 &lambda = m_bend_lambda[BendLambdaKey(a, b, c, true, 0.0, k)];
        const Vector3 delta_lambda = (delta - lambda * alpha) / (w_total + alpha);
        lambda += delta_lambda;
        m_points[b] += delta_lambda * w_b;
        m_points[c] -= delta_lambda * (0.5f * w_c);
    }
    else
    {
        m_points[b] += v * (w_b / w_total);
        m_points[c] -= v * (0.5f * w_c / w_total);
    }
}

uint64_t VerletRope::BendLambdaKey(int a, int b, int c, bool anchored,
                                   double allowed_dev, double strength) const
{
    uint64_t key = (static_cast<uint64_t>(anchored) << 63) |
                   (static_cast<uint64_t>(a & 0x1fffff) << 42) |
                   (static_cast<uint64_t>(b & 0x1fffff) << 21) |
                   static_cast<uint64_t>(c & 0x1fffff);
    // The same triple may carry both the ordinary cable bend and a stronger
    // strain-relief constraint. Keep their multipliers independent.
    key ^= static_cast<uint64_t>(std::hash<double>{}(allowed_dev)) * 0x9e3779b97f4a7c15ULL;
    key ^= static_cast<uint64_t>(std::hash<double>{}(strength)) * 0xbf58476d1ce4e5b9ULL;
    return key;
}

// Keep segment s's midpoint outside its cached contact plane, splitting the
// correction so the midpoint clears fully. The distance cap guards against stale
// planes (refreshed only every raycast_interval frames, and infinite in extent).
inline void VerletRope::SolveMidContact(int s, bool second)
{
    const int ia = m_seg_a[s];
    const int ib = m_seg_b[s];
    const float w_a = m_inv_mass[ia];
    const float w_b = m_inv_mass[ib];
    const float w_sum = w_a + w_b;
    if (w_sum == 0.0f)
        return;
    const double t = second ? m_mid_contact_t_2[s] : m_mid_contact_t[s];
    const double ta = 1.0 - t;
    const Vector3 mid = m_points[ia] * ta + m_points[ib] * t;
    const double rest = m_seg_rest[s];
    const Vector3 &contact_point = second ? m_mid_contact_point_2[s] : m_mid_contact_point[s];
    const Vector3 &contact_normal = second ? m_mid_contact_normal_2[s] : m_mid_contact_normal[s];
    if (mid.distance_squared_to(contact_point) > rest * rest * 4.0)
        return;
    const Vector3 n = contact_normal;
    const double d = (mid - contact_point).dot(n);
    if (d >= m_collision_radius)
        return;
    double push_distance = m_collision_radius - d;
    if (m_contact_compliance > 0.0)
    {
        const double alpha = m_contact_compliance / m_step_dt_sq;
        double &lambda = second ? m_mid_contact_lambda_2[s] : m_mid_contact_lambda[s];
        const double old_lambda = lambda;
        const double weight = w_a * ta * ta + w_b * t * t;
        const double delta_lambda = (push_distance - alpha * old_lambda) / (weight + alpha);
        lambda = std::max(0.0, old_lambda + delta_lambda);
        push_distance = lambda - old_lambda;
        m_points[ia] += n * (ta * w_a * push_distance);
        m_points[ib] += n * (t * w_b * push_distance);
    }
    else
    {
        const Vector3 push = n * push_distance;
        const double weight = w_a * ta * ta + w_b * t * t;
        if (weight <= 0.0)
            return;
        (second ? m_mid_contact_lambda_2[s] : m_mid_contact_lambda[s]) += push_distance;
        m_points[ia] += push * (w_a * ta / weight);
        m_points[ib] += push * (w_b * t / weight);
    }
}

// Keep particle i at least collision_radius outside the cached plane.
inline void VerletRope::ProjectPlane(int i, const Vector3 &cp, const Vector3 &n, double &lambda)
{
    const double d = (m_points[i] - cp).dot(n);
    if (d < m_collision_radius)
    {
        if (m_contact_compliance <= 0.0)
        {
            // No multiplier on this path, but friction still needs to know how
            // hard the surface pushed back: record the push distance itself.
            lambda += m_collision_radius - d;
            m_points[i] += n * (m_collision_radius - d);
            return;
        }
        const double alpha = m_contact_compliance / m_step_dt_sq;
        const double delta_lambda = (m_collision_radius - d - alpha * lambda) /
                                    (m_inv_mass[i] + alpha);
        const double old_lambda = lambda;
        lambda = std::max(0.0, lambda + delta_lambda);
        m_points[i] += n * (m_inv_mass[i] * (lambda - old_lambda));
    }
}

void VerletRope::PinAnchors()
{
    // With substeps a pinned end is carried to its anchor over the slices of
    // the tick, not thrown there in the first one.
    const bool part = m_pin_fraction < 1.0 && m_pin_from.size() == 2 + m_fray.size();
    if (m_start_cached)
    {
        m_points[0] = AnchorPoint(m_start_cached, m_start_anchor_offset, m_points[0]);
        if (part)
            m_points[0] = m_pin_from[0].lerp(m_points[0], m_pin_fraction);
        m_prev_points[0] = m_points[0];
    }
    if (m_end_cached)
    {
        const int last = TrunkCount() - 1;
        m_points[last] = AnchorPoint(m_end_cached, m_end_anchor_offset, m_points[last]);
        if (part)
            m_points[last] = m_pin_from[1].lerp(m_points[last], m_pin_fraction);
        m_prev_points[last] = m_points[last];
    }
    for (size_t g = 0; g < m_fray.size(); ++g)
    {
        const FrayChain &fc = m_fray[g];
        if (fc.cached == nullptr)
            continue;
        const int last = fc.first + fc.count - 1;
        m_points[last] = AnchorPoint(fc.cached, fc.offset, m_points[last]);
        if (part)
            m_points[last] = m_pin_from[2 + g].lerp(m_points[last], m_pin_fraction);
        m_prev_points[last] = m_points[last];
    }
}

// True when an anchor is further from the particle pinned to it than it could have
// been carried since the last tick. PinAnchors puts that particle exactly on the
// anchor every tick, so the gap IS how far the anchor moved, and no extra state is
// needed to measure it.
bool VerletRope::AnchorTeleported() const
{
    if (m_points.empty())
        return false;
    if (m_start_cached != nullptr &&
        AnchorPoint(m_start_cached, m_start_anchor_offset, m_points[0])
                .distance_squared_to(m_points[0]) > TELEPORT_EPS_SQ)
        return true;
    if (m_end_cached != nullptr)
    {
        const int last = TrunkCount() - 1;
        if (AnchorPoint(m_end_cached, m_end_anchor_offset, m_points[last])
                .distance_squared_to(m_points[last]) > TELEPORT_EPS_SQ)
            return true;
    }
    for (const FrayChain &fc : m_fray)
    {
        if (fc.cached == nullptr)
            continue;
        const int last = fc.first + fc.count - 1;
        if (AnchorPoint(fc.cached, fc.offset, m_points[last]).distance_squared_to(m_points[last]) >
            TELEPORT_EPS_SQ)
            return true;
    }
    return false;
}

// Snap point i to just outside a surface and convert its velocity into a
// friction-damped slide along the surface (no bounce).
inline void VerletRope::ResolveContact(int i, const Vector3 &contact, const Vector3 &normal)
{
    const Vector3 vel = m_points[i] - m_prev_points[i];
    const Vector3 tangential = vel - normal * vel.dot(normal);
    m_points[i] = contact + normal * m_collision_radius;
    m_prev_points[i] = m_points[i] - tangential * (1.0 - m_surface_friction);
}

// Stub stiffness at the k-th particle from an end (k = 1 nearest), over n stub
// particles. Full strength at the plug, easing to nothing at the far end — a
// constant strength across the stub made the cable look like sausage links,
// because a rigid run met a floppy run at a hard boundary.
double VerletRope::StubWeight(double base, int k, int n) const
{
    if (n <= 1)
        return base;
    return base * (1.0 - static_cast<double>(k - 1) / static_cast<double>(n));
}

// Whether a cached contact plane is still plausible for particle i: the particle
// hasn't slid far from the contact and still sits near the plane.
bool VerletRope::PlaneValid(int i, const Vector3 &cp, const Vector3 &n) const
{
    const Vector3 p = m_points[i];
    if (p.distance_squared_to(cp) > m_segment_length * m_segment_length * 4.0)
        return false;
    return std::abs((p - cp).dot(n)) < m_collision_radius * 3.0;
}

// ── Plug orientation ────────────────────────────────────────────────────────

// True when this anchor's orientation is externally fixed, so the cable should
// leave it stiffly along its exit axis rather than hanging freely. That covers a
// host attach point (a plain Node3D bolted to a device) and a plug that's held
// or socketed. A free-dangling plug is NOT fixed — it follows the rope instead.
VerletRope::EndpointRole VerletRope::ResolveEndpointRole(Node3D *node, int configured_role) const
{
    if (node == nullptr)
        return ENDPOINT_FREE_PLUG;
    if (configured_role >= ENDPOINT_HOST && configured_role <= ENDPOINT_SOCKETED_PLUG)
        return static_cast<EndpointRole>(configured_role);
    RigidBody3D *rb = Object::cast_to<RigidBody3D>(node);
    if (rb == nullptr)
        return ENDPOINT_HOST;
    if (rb->has_method("is_plugged_in") && static_cast<bool>(rb->call("is_plugged_in")))
        return ENDPOINT_SOCKETED_PLUG;
    if (rb->has_method("is_picked_up") && static_cast<bool>(rb->call("is_picked_up")))
        return ENDPOINT_HELD_PLUG;
    if (rb->is_freeze_enabled())
        return ENDPOINT_HELD_PLUG; // legacy test/tool stand-in for a held plug
    return ENDPOINT_FREE_PLUG;
}

bool VerletRope::EndpointIsFixed(EndpointRole role)
{
    return role != ENDPOINT_FREE_PLUG;
}

bool VerletRope::EndpointIsDirectional(EndpointRole role)
{
    // A host attachment is the fixed moulded end of a controller, sensor bar,
    // speaker, etc. Its authored exit axis is exactly what gives the nearby
    // segments their visible strain relief. Held plugs also carry orientation
    // authority from the player's hand. A seated plug is equally authored by
    // its socket: changing role must not make its moulded strain relief vanish.
    // Surface contacts are solved after this constraint and still keep the boot
    // out of the panel or nearby furniture.
    return role == ENDPOINT_HOST || role == ENDPOINT_HELD_PLUG ||
           role == ENDPOINT_SOCKETED_PLUG;
}

bool VerletRope::EndpointIsFree(EndpointRole role)
{
    return role == ENDPOINT_FREE_PLUG;
}

bool VerletRope::PlugIsFixed(Node3D *node) const
{
    return EndpointIsFixed(ResolveEndpointRole(node, ENDPOINT_AUTO));
}

Vector3 VerletRope::PlugExitDir(Node3D *node, const Vector3 &axis) const
{
    if (node == nullptr)
        return Vector3();
    return (node->get_global_transform().basis.orthonormalized().xform(axis)).normalized();
}

// A loose plug the cord is coupled to: a RigidBody3D in the FREE role, on a
// rope whose end_align_stiffness is non-zero. Its orientation is its own, so
// the cord leaves along its exit axis as it does from a held plug — but the
// plug is free to answer back, through CouplePlug.
//
// The configured role wins, as everywhere else: the VRU authors its microphone
// end as a HOST, and a coupling that re-derived the role from the node pushed
// the microphone across the floor (n64_vru_tests "stays where it landed").
bool VerletRope::PlugIsCoupled(Node3D *node, int p_configured_role) const
{
    if (m_end_align_stiffness <= 0.0 || node == nullptr)
        return false;
    if (Object::cast_to<RigidBody3D>(node) == nullptr)
        return false;
    return ResolveEndpointRole(node, p_configured_role) == ENDPOINT_FREE_PLUG;
}

// Push a loose plug with what the cord did to it this step.
//
// m_pin_push is how far the pinned particle would have moved had it been free,
// summed over the solve; over a step of dt that is a force of m x push / dt^2,
// with m the mass of one segment of cord. The moment term is the boot: it bent
// the cord's first segments onto the plug's exit axis, and the plug takes the
// equal and opposite turn. Both go to the physics server as ordinary forces,
// so the plug's own contacts, friction and sleep decide where it ends up.
//
// This replaced AlignAnchorPlug, which rotated the plug onto the cord's tangent
// with a transform write every tick. On a floor that turn swung the body into
// the surface, the server pushed it back out, the pinned cord end moved with it
// and the next turn started over — the ends of a cord lying on the floor
// squirmed until the rope happened to fall asleep.
void VerletRope::CouplePlug(Node3D *node, int p_configured_role, const Vector3 &offset, int p_slot,
                            double p_segment_length)
{
    if (!PlugIsCoupled(node, p_configured_role) || m_linear_density <= 0.0)
        return;
    if (p_slot < 0 || p_slot >= static_cast<int>(m_pin_push.size()))
        return;
    RigidBody3D *rb = Object::cast_to<RigidBody3D>(node);
    // The push is summed over the tick's slices, each a displacement over a
    // slice's dt^2: the force is their MEAN over that.
    const int slices = std::max(1, m_substeps);
    const double scale = m_linear_density * p_segment_length / (m_step_dt_sq * slices);
    Vector3 force = m_pin_push[p_slot] * scale;
    Vector3 torque = m_pin_moment[p_slot] * scale;
    if (force.length_squared() < 1e-14 && torque.length_squared() < 1e-14)
        return;

    const double dt = std::sqrt(m_step_dt_sq) * slices;
    const double mass = rb->get_mass();
    if (mass > 0.0)
    {
        const double dv = force.length() / mass * dt;
        if (dv > MAX_COUPLE_DV)
            force *= MAX_COUPLE_DV / dv;
    }
    const double dw = (rb->get_inverse_inertia_tensor().xform(torque) * dt).length();
    if (dw > MAX_COUPLE_DW)
        torque *= MAX_COUPLE_DW / dw;

    const Vector3 anchor = AnchorPoint(node, offset, Vector3());
    rb->apply_force(force, anchor - rb->get_global_position());
    rb->apply_torque(torque);
}

// ── Tick ────────────────────────────────────────────────────────────────────

void VerletRope::_physics_process(double p_delta)
{
    Step(p_delta);
}

void VerletRope::Step(double p_delta)
{
    if (m_points.empty())
        return;
    const int substeps = std::max(1, m_substeps);
    const double slice = p_delta / substeps;
    m_step_dt_sq = std::max(slice * slice, 1e-8);

    ReconcileAnchors();

    // A socket taking a plug, or a save putting a device back where it was left,
    // moves an anchor across the room between one tick and the next. Dragging the
    // cord after it — which is what the solver does with every other kind of
    // motion — hauls the whole length through the desk and whatever is standing on
    // it, and the cord can take seconds to arrive. Lay it out afresh between the
    // anchors' new positions instead, which is where it would have been built had
    // they been in place at the time.
    if (AnchorTeleported())
    {
        InitPoints();
        return;
    }

    if (m_depen_pending)
    {
        m_depen_pending = false;
        DepenetrateLay();
    }

    if (m_asleep)
    {
        if (AnchorsMoved())
        {
            m_diag_wake_anchor += 1;
            Wake();
            m_diag_wake_call -= 1;
        }
        else if (++m_sleep_environment_frame >= SLEEP_ENVIRONMENT_INTERVAL)
        {
            m_sleep_environment_frame = 0;
            if (EnvironmentChangedWhileSleeping())
            {
                // Edge queries can return a different face (or no face) on one
                // poll although nothing moved. Require the same conclusion on
                // two polls; a removed or intruding support persists, an
                // alternating-normal false positive does not.
                m_environment_change_polls += 1;
                if (m_environment_change_polls < 2)
                    return;
                m_environment_change_polls = 0;
                m_diag_wake_env += 1;
                Wake();
                m_diag_wake_call -= 1;
                // The poll now discounts shallow "inside" reports already
                // explained by a valid cached plane, so a confirmed result is
                // a real removal or intrusion. Discard the old arrangement and
                // free any particles newly covered by moved furniture.
                std::fill(m_c_flags.begin(), m_c_flags.end(), 0);
                std::fill(m_mid_contact.begin(), m_mid_contact.end(), 0);
                std::fill(m_stuck_passes.begin(), m_stuck_passes.end(), 0);
                DepenetrateLay();
                m_raycast_frame = m_raycast_interval;
            }
            else
                m_environment_change_polls = 0;
        }
        if (m_asleep)
        {
            // Nothing moved, so there is nothing to interpolate between; leaving
            // this true would re-mesh a settled cable every frame forever.
            m_interpolating = false;
            // Except a ribbon's LAY, which is drawn from its connectors' bases:
            // turning a plug about its own cord axis moves no anchor, so the rope
            // sleeps on, and the wires stayed where they were while the plug
            // rolled underneath them. Re-mesh (never re-simulate) when it does.
            if (RibbonEndsTurned())
                m_mesh_dirty = true;
            return;
        }
    }
    m_mesh_dirty = true;

    // What the cord does to its pinned ends is summed over the whole tick.
    m_pin_push.assign(2 + m_fray.size(), Vector3());
    m_pin_moment.assign(2 + m_fray.size(), Vector3());
    // Where the pinned ends were, before the first slice carries them on.
    m_pin_from.resize(2 + m_fray.size());
    m_pin_from[0] = m_points[0];
    m_pin_from[1] = m_points[TrunkCount() - 1];
    m_pin_velocity.assign(2, Vector3());
    if (m_start_cached)
        m_pin_velocity[0] = (AnchorPoint(m_start_cached, m_start_anchor_offset, m_points[0]) -
                             m_points[0]) / static_cast<double>(substeps);
    if (m_end_cached)
        m_pin_velocity[1] = (AnchorPoint(m_end_cached, m_end_anchor_offset,
                                         m_points[TrunkCount() - 1]) -
                             m_points[TrunkCount() - 1]) / static_cast<double>(substeps);
    for (size_t g = 0; g < m_fray.size(); ++g)
        m_pin_from[2 + g] = m_points[m_fray[g].first + m_fray[g].count - 1];
    if (substeps > 1)
        m_tick_from = m_points;
    m_pin_fraction = 1.0 / substeps;
    Integrate(slice);
    m_self_contacts.clear();
    if (m_self_collision)
        DetectSelfContacts();

    // End orientation authority: a plug whose orientation is externally fixed
    // drives the ROPE. A free plug and its cord settle it between them — the
    // cord leaves along the plug, the plug takes the cord's reaction as forces
    // (see CouplePlug after the solve).
    const EndpointRole start_role = ResolveEndpointRole(m_start_cached, m_start_endpoint_role);
    const EndpointRole end_role = ResolveEndpointRole(m_end_cached, m_end_endpoint_role);
    const bool start_fixed = EndpointIsFixed(start_role);
    const bool end_fixed = EndpointIsFixed(end_role);
    // Hosts, held plugs and seated plugs all have authored orientation and keep
    // the moulded strain-relief stub when their endpoint role changes. A coupled
    // loose plug keeps it too: the plug's own orientation is physical now, and
    // the stub's reaction is what turns it (see CouplePlug).
    const bool start_directional = EndpointIsDirectional(start_role) ||
                                   (!start_fixed && PlugIsCoupled(m_start_cached, m_start_endpoint_role));
    const bool end_directional = EndpointIsDirectional(end_role) ||
                                 (!end_fixed && PlugIsCoupled(m_end_cached, m_end_endpoint_role));
    const Vector3 start_exit =
        start_directional ? PlugExitDir(m_start_cached, m_start_exit_axis) : Vector3();
    const Vector3 end_exit = end_directional ? PlugExitDir(m_end_cached, m_end_exit_axis) : Vector3();

    m_iterations_now = std::max(1, static_cast<int>(std::lround(
                                       static_cast<double>(std::max(m_constraint_iterations, 1)) / substeps)));
    SolveConstraints(start_directional, end_directional, start_exit, end_exit);
    FinishSelfContacts();
    ApplyContactFriction();
    for (int k = 1; k < substeps; ++k)
    {
        // The same contacts, found at the tick's start, for every slice.
        m_pin_fraction = static_cast<double>(k + 1) / substeps;
        Integrate(slice);
        for (SelfContact &c : m_self_contacts)
            c.pushed = 0.0;
        std::fill(m_self_moved.begin(), m_self_moved.end(), Vector3());
        SolveConstraints(start_directional, end_directional, start_exit, end_exit);
        FinishSelfContacts();
        ApplyContactFriction();
    }
    m_pin_fraction = 1.0;

    // Cadence shared by the heavier environment queries below.
    m_raycast_frame += 1;
    const bool do_rest = m_raycast_frame >= m_raycast_interval;
    if (do_rest)
        m_raycast_frame = 0;

    if (m_surface_collision_mask != 0 && m_ray_query.is_valid())
        SolveSurfaceCollision(do_rest);

    ApplyAnchorCoupling();

    // Loose plugs answer the cord through forces, FREE ends only.
    CouplePlug(m_start_cached, m_start_endpoint_role, m_start_anchor_offset, 0, m_segment_length);
    CouplePlug(m_end_cached, m_end_endpoint_role, m_end_anchor_offset, 1, m_segment_length);
    for (size_t g = 0; g < m_fray.size(); ++g)
        CouplePlug(m_fray[g].cached, ENDPOINT_AUTO, m_fray[g].offset, 2 + static_cast<int>(g),
                   FraySegLength());

    UpdateSleepState();
    // Last thing in the tick, after the anchors are pinned: roll the render
    // history forward so _process has two states to interpolate between.
    SnapshotRenderState();
}

// A stiffness given as "the share of the error one iteration takes out", for a
// slice of the tick. What a share amounts to physically goes with dt^2 (it is a
// compliance over dt^2), so the same share over slices 1/n as long is a
// constraint n^2 times as stiff: a cord rated 0.2 stood up like wire at four
// substeps (rope_tests "the cord lies down": 325 mm tall). Scaled by 1/n^2, and
// by the iterations a slice has against a whole step's, a hanging loop takes
// the shape it had at one step a tick (0.6 m between sockets 0.1 m apart, rated
// 0.2: 259 mm deep against 260; rated 0.3: 255 against 256). 1 stays rigid.
double VerletRope::SliceStiffness(double p_k) const
{
    if (m_substeps <= 1 || p_k <= 0.0 || p_k >= 1.0)
        return p_k;
    const double full = std::max(m_constraint_iterations, 1);
    const double now = std::max(m_iterations_now, 1);
    const double n_sq = static_cast<double>(m_substeps) * m_substeps;
    return std::min(p_k, p_k * full / (now * n_sq));
}

void VerletRope::Integrate(double p_delta)
{
    const int count = static_cast<int>(m_points.size());
    const Vector3 grav_step = m_gravity * (p_delta * p_delta);
    // Damping is per TICK: a slice keeps the root of what a tick keeps.
    const double retain = m_substeps > 1 ? std::pow(1.0 - m_damping, 1.0 / m_substeps)
                                         : 1.0 - m_damping;
    // Internal damping (substeps only): each particle's velocity is drawn a
    // little toward the mean of its two neighbours'. One step of eight
    // iterations damped a cord's fast transverse waves heavily and by accident;
    // slices of two iterations do not, and a hanging span buzzed after every
    // move of its end. The cord's motion as a whole is not touched: only how
    // much a particle's velocity differs from the cord either side of it.
    if (m_substeps > 1 && m_wave_damping > 0.0)
    {
        m_velocity_scratch.resize(count);
        for (int i = 0; i < count; ++i)
            m_velocity_scratch[i] = m_points[i] - m_prev_points[i];
        const int trunk = TrunkCount();
        // A pinned end's velocity is its anchor's (its own history is reset
        // every time it is pinned): a cord swinging between two fixed sockets
        // loses its swing to them, as it does to a real cord's ends.
        if (m_start_cached && m_pin_velocity.size() >= 2)
            m_velocity_scratch[0] = m_pin_velocity[0];
        if (m_end_cached && m_pin_velocity.size() >= 2)
            m_velocity_scratch[trunk - 1] = m_pin_velocity[1];
        for (int i = 1; i < trunk - 1; ++i)
        {
            if (m_inv_mass[i] == 0.0f)
                continue;
            const Vector3 mean = (m_velocity_scratch[i - 1] + m_velocity_scratch[i + 1]) * 0.5;
            m_prev_points[i] -= (mean - m_velocity_scratch[i]) * m_wave_damping;
        }
    }
    for (int i = 0; i < count; ++i)
    {
        if (m_inv_mass[i] == 0.0f)
            continue;
        const Vector3 current = m_points[i];
        const Vector3 velocity = (current - m_prev_points[i]) * retain;
        m_prev_points[i] = current;
        m_points[i] = current + velocity + grav_step;
    }
    PinAnchors();
}

void VerletRope::SolveConstraints(bool p_start_fixed, bool p_end_fixed,
                                  const Vector3 &p_start_exit, const Vector3 &p_end_exit)
{
    // The trunk's own particle range. Without a fray this is every particle, so
    // all the loops below are exactly what they were.
    const int count = TrunkCount();
    const int seg_count = static_cast<int>(m_seg_a.size());
    const int iters = m_iterations_now > 0 ? m_iterations_now
                                           : (m_constraint_iterations > 1 ? m_constraint_iterations : 1);
    // Once a slice now, so only what is in use is cleared.
    if (m_stretch_compliance > 0.0 || m_stretch_lambda.size() != static_cast<size_t>(seg_count))
        m_stretch_lambda.assign(seg_count, 0.0);
    m_mid_contact_lambda.assign(seg_count, 0.0);
    m_mid_contact_lambda_2.assign(seg_count, 0.0);
    m_contact_lambda_1.assign(m_points.size(), 0.0);
    m_contact_lambda_2.assign(m_points.size(), 0.0);
    if (!m_bend_lambda.empty())
        m_bend_lambda.clear();
    if (!m_angle_lambda.empty())
        m_angle_lambda.clear();

    // Stretch stiffness is remapped so extensibility is independent of the
    // iteration count (k' = 1-(1-k)^(1/n)); 1.0 stays fully rigid.
    const double k_stretch = 1.0 - std::pow(1.0 - CLAMP(m_stretch_stiffness, 0.0, 1.0), 1.0 / iters);
    // Bend stiffness is applied directly per iteration — remapping it the same
    // way crushes mid-range values into "floppy" at typical iteration counts.
    const double k_bend = SliceStiffness(CLAMP(m_bend_stiffness, 0.0, 1.0));
    // Angular projection is stronger than the old midpoint displacement for
    // the same numeric rating. Preserve the authored cable feel while making
    // the value iteration-count independent.
    // A bend of angle B deviates the particle L*sin(B/2) from the midpoint;
    // bends up to max_bend_degrees are free.
    const double allowed_dev = m_segment_length * std::sin(Math::deg_to_rad(m_max_bend_degrees) * 0.5);

    UpdateEdgeContacts();

    // Contact flags are only rewritten by the throttled rest pass, never inside
    // the solve, so gather the active planes once instead of re-testing every
    // particle on all eight iterations.
    m_active_mid.clear();
    for (int s = 0; s < seg_count; ++s)
        if (m_mid_contact[s] != 0)
            m_active_mid.push_back(s);
    m_active_contact.clear();
    for (int i = 0, n = static_cast<int>(m_points.size()); i < n; ++i)
        if (m_inv_mass[i] != 0.0f && m_c_flags[i] != 0)
            m_active_contact.push_back(i);

    for (int iter_i = 0; iter_i < iters; ++iter_i)
    {
        // Stretch runs off the segment table, so a branch's link back to the
        // junction is solved with the rest, at the branch's own rest length.
        for (int s = 0; s < seg_count; ++s)
            SolvePair(m_seg_a[s], m_seg_b[s], m_seg_rest[s], k_stretch,
                      m_stretch_compliance > 0.0 ? &m_stretch_lambda[s] : nullptr);

        // Bend, hierarchical: adjacent midpoint bending preserves the existing
        // cable drape, while spacing 2/4/8 keeps long ropes from saturating.
        if (k_bend > 0.0)
        {
            int levels = 1 + static_cast<int>(std::lround(CLAMP(m_bend_stiffness, 0.0, 1.0) * 3.0));
            int s = 1;
            while (s * 2 <= count - 1 && levels > 0)
            {
                const double allowed = allowed_dev * static_cast<double>(s * s);
                if (iter_i % 2 == 0)
                    for (int i = s; i < count - s; ++i)
                        SolveBend(i, s, allowed, k_bend);
                else
                    for (int i = count - s - 1; i >= s; --i)
                        SolveBend(i, s, allowed, k_bend);
                s *= 2;
                levels -= 1;
            }
        }

        // End stiffness (strain-relief boot): hold the first/last few segments
        // perfectly straight with a strong direct stiffness, so the cable
        // emerges rigid from each plug and only bends past the stub. Applied
        // after the general bend so it wins near the ends.
        if (m_end_stiffness > 0.0 && m_end_stiff_segments > 0)
        {
            const double ke = SliceStiffness(CLAMP(m_end_stiffness, 0.0, 1.0));
            const int n_end = std::min(m_end_stiff_segments, (count - 1) / 2);
            if (iter_i % 2 == 0)
            {
                for (int i = 1; i <= n_end; ++i)
                    SolveBend(i, 1, 0.0, StubWeight(ke, i, n_end));
                for (int i = count - 2; i > count - 2 - n_end; --i)
                    SolveBend(i, 1, 0.0, StubWeight(ke, count - 1 - i, n_end));
            }
            else
            {
                for (int i = n_end; i >= 1; --i)
                    SolveBend(i, 1, 0.0, StubWeight(ke, i, n_end));
                for (int i = count - 1 - n_end; i < count - 1; ++i)
                    SolveBend(i, 1, 0.0, StubWeight(ke, count - 1 - i, n_end));
            }
        }

        // Adjacent segments cannot self-collide. Only in the severe-fold region
        // add nonlinear angular resistance and the hard per-joint limit.
        if (k_bend > 0.0 || m_bend_limit_degrees < 180.0)
        {
            if (iter_i % 2 == 0)
                for (int i = 1; i < count - 1; ++i)
                    SolveAngleBend(i - 1, i, i + 1, 0.0, k_bend);
            else
                for (int i = count - 2; i >= 1; --i)
                    SolveAngleBend(i - 1, i, i + 1, 0.0, k_bend);
        }

        // Directional strain-relief stub: pull the first/last few particles
        // onto the authored exit line of a host, held plug or seated plug.
        if (m_end_stiffness > 0.0 && m_end_stiff_segments > 0 &&
            (p_start_fixed || p_end_fixed))
        {
            const double ked = SliceStiffness(CLAMP(m_end_stiffness, 0.0, 1.0));
            const int nd = std::min(m_end_stiff_segments, (count - 1) / 2);
            if (p_end_fixed)
            {
                const Vector3 base_e = m_points[count - 1];
                for (int j = 1; j <= nd; ++j)
                {
                    const int idx = count - 1 - j;
                    if (m_inv_mass[idx] != 0.0f)
                    {
                        const Vector3 before = m_points[idx];
                        m_points[idx] = m_points[idx].lerp(
                            base_e + p_end_exit * (m_segment_length * j),
                            StubWeight(ked, j, nd));
                        AddPinReaction(count - 1, before - m_points[idx], before - base_e);
                    }
                }
            }
            if (p_start_fixed)
            {
                const Vector3 base_s = m_points[0];
                for (int j = 1; j <= nd; ++j)
                {
                    if (m_inv_mass[j] != 0.0f)
                    {
                        const Vector3 before = m_points[j];
                        m_points[j] = m_points[j].lerp(
                            base_s + p_start_exit * (m_segment_length * j),
                            StubWeight(ked, j, nd));
                        AddPinReaction(0, before - m_points[j], before - base_s);
                    }
                }
            }
        }

        if (!m_fray.empty())
            SolveFrayConstraints(iter_i, k_stretch, k_bend, allowed_dev);

        // The cord against itself, BEFORE the surfaces: what a crossing pushes
        // into the floor, the floor's own plane puts back in this same pass.
        SolveSelfContacts();

        // Cached contact planes, solved together with the other constraints so
        // contacts — including edge wraps — are part of the equilibrium instead
        // of oscillating.
        for (int s : m_active_mid)
        {
            if (m_mid_contact[s] & 1)
                SolveMidContact(s, false);
            if (m_mid_contact[s] & 2)
                SolveMidContact(s, true);
        }
        for (int i : m_active_contact)
        {
            const uint8_t flags = m_c_flags[i];
            if (flags & 1)
                ProjectPlane(i, m_c_p1[i], m_c_n1[i], m_contact_lambda_1[i]);
            if (flags & 2)
                ProjectPlane(i, m_c_p2[i], m_c_n2[i], m_contact_lambda_2[i]);
        }
        PinAnchors();
    }
}

// Bend and stub constraints for the frayed branches. Stretch is not here — it
// comes off the shared segment table with the trunk's.
//
// A branch gets a strain-relief boot at BOTH ends, the plug and the breakout.
// The breakout one matters more than it sounds: a moulded fray is stiff where
// the cords leave it, so they carry the trunk's direction out for a few
// centimetres and curve away under their own weight. Left as a free hinge — which
// this deliberately was, on the reasoning that a fray point is a hinge — gravity
// turns every cord vertically downward the instant it separates, and the fray
// reads as three wires dropped out of a hole rather than a moulded breakout.
void VerletRope::SolveFrayConstraints(int p_iter, double, double p_k_bend, double p_allowed_dev)
{
    const double seg_len = FraySegLength();
    for (const FrayChain &fc : m_fray)
    {
        const int first = fc.first;
        const int last = fc.first + fc.count - 1;
        if (fc.count < 3)
            continue;

        if (p_k_bend > 0.0)
        {
            int levels = 1 + static_cast<int>(std::lround(CLAMP(m_bend_stiffness, 0.0, 1.0) * 3.0));
            int s = 1;
            while (s * 2 <= fc.count - 1 && levels > 0)
            {
                const double allowed = p_allowed_dev * static_cast<double>(s * s);
                if (p_iter % 2 == 0)
                    for (int i = first + s; i <= last - s; ++i)
                        SolveBend(i, s, allowed, p_k_bend);
                else
                    for (int i = last - s; i >= first + s; --i)
                        SolveBend(i, s, allowed, p_k_bend);
                // `first` sits one short of that range at every spacing, and its
                // low neighbour is the junction — a different chain, so the
                // spacing form cannot reach it. It is picked up by the breakout
                // boot below instead of here: adding it at every iteration piles
                // a second constraint per branch onto the junction, and with
                // three branches that fight was enough to stop a lead settling
                // on a table edge (asleep 107/200 of the tail, down to 34).
                s *= 2;
                levels -= 1;
            }
        }

        if (p_k_bend > 0.0 || m_bend_limit_degrees < 180.0)
        {
            if (p_iter % 2 == 0)
                for (int i = first + 1; i < last; ++i)
                    SolveAngleBend(i - 1, i, i + 1, 0.0, p_k_bend);
            else
                for (int i = last - 1; i > first; --i)
                    SolveAngleBend(i - 1, i, i + 1, 0.0, p_k_bend);
        }

        // Strain-relief boot at the plug, the same taper the trunk's ends get.
        if (m_end_stiffness > 0.0 && m_end_stiff_segments > 0)
        {
            const double ke = SliceStiffness(CLAMP(m_end_stiffness, 0.0, 1.0));
            const int n_end = std::min(m_end_stiff_segments, fc.count - 2);
            for (int j = 1; j <= n_end; ++j)
                SolveBend(last - j, 1, 0.0, StubWeight(ke, j, n_end));

            // …and at the breakout. The first triple spans the junction, holding
            // the branch on the line the trunk arrives along; the rest taper it
            // off into the branch exactly as the plug's boot does.
            const int trunk_n = TrunkCount();
            const int trunk_prev = fc.at_start ? 1 : trunk_n - 2;
            const int n_head = std::min(m_end_stiff_segments, fc.count - 1);
            if (trunk_n >= 2 && n_head > 0)
            {
                // Two triples, not one. The first holds the JUNCTION straight
                // between the trunk and the branch; the second holds the
                // branch's first particle, whose low neighbour is that junction
                // and so is out of reach of the contiguous form below.
                SolveBendTriple(trunk_prev, fc.head, first, 0.0, StubWeight(ke, 1, n_head));
                SolveBendAnchored(fc.head, first, first + 1, StubWeight(ke, 1, n_head));
                for (int j = 1; j < n_head; ++j)
                    SolveBend(first + j, 1, 0.0, StubWeight(ke, j + 1, n_head));
            }

            // Directional stub: a branch whose plug is held or socketed leaves
            // it along the plug's exit axis rather than hanging off it, and so
            // does one whose loose plug is coupled — its body takes the stub's
            // reaction as a torque, so the plug and its boot turn together.
            if (fc.cached != nullptr && (PlugIsFixed(fc.cached) || PlugIsCoupled(fc.cached, ENDPOINT_AUTO)))
            {
                const Vector3 exit = PlugExitDir(fc.cached, m_end_exit_axis);
                const Vector3 base = m_points[last];
                for (int j = 1; j <= n_end; ++j)
                {
                    const int idx = last - j;
                    if (m_inv_mass[idx] != 0.0f)
                    {
                        const Vector3 before = m_points[idx];
                        m_points[idx] = m_points[idx].lerp(base + exit * (seg_len * j),
                                                           StubWeight(ke, j, n_end));
                        AddPinReaction(last, before - m_points[idx], before - base);
                    }
                }
            }
        }
    }
}

// Coulomb friction for cached resting contacts, once per step after the solve,
// on VELOCITY only.
//
// The load is how far the contact planes pushed a particle back out this step
// (the accumulated contact multipliers, summed over every plane and segment
// midpoint bearing on it). A resting point is pushed back by one step of
// gravity, so the load is g dt^2 and "tangential step < mu x load" is exactly
// "friction force < mu x weight"; a cord pulled round an edge is pressed
// harder and grips harder, as a real one does. Applied along the plane
// bearing hardest on the particle.
//
// Inside the static cone the tangential velocity is zeroed outright — the
// point stops dead instead of coasting on at 60%. Outside it, kinetic_friction
// x load comes off it each step, a deceleration of mu g, never past zero.
//
// Positions are never touched, deliberately. A stick applied to positions
// fights the rigid stretch constraints: once after the solve it left them
// unsatisfied and the unstuck neighbours were hauled every tick (a composite
// lead's breakout loop crawled for seconds on the floor); inside the loop it
// held points against pulls the stretch re-applied in small steps (a cord
// hauled round a post stretched to twice its length), and budgeting the grip
// over the iterations pumped a heap that never slept. What a velocity stick
// cannot do is hold a point against a steady pull — a slope creeps — but at a
// crawl the sleep system already parks.
//
// With both coefficients zero this is the old viscous damping instead: keep a
// (1 - surface_friction) share of every contact's tangential velocity, which
// never brought a slow slide to zero.
void VerletRope::ApplyContactFriction()
{
    const int count = static_cast<int>(m_points.size());
    if (m_static_friction <= 0.0 && m_kinetic_friction <= 0.0)
    {
        for (int i = 0; i < count; ++i)
        {
            if (m_inv_mass[i] == 0.0f || m_c_flags[i] == 0)
                continue;
            for (int slot = 0; slot < 2; ++slot)
            {
                if ((m_c_flags[i] & (1 << slot)) == 0)
                    continue;
                const Vector3 n = slot == 0 ? m_c_n1[i] : m_c_n2[i];
                const Vector3 cp = slot == 0 ? m_c_p1[i] : m_c_p2[i];
                if ((m_points[i] - cp).dot(n) > m_collision_radius * 1.05)
                    continue;
                const Vector3 vel = m_points[i] - m_prev_points[i];
                const Vector3 tangential = vel - n * vel.dot(n);
                m_prev_points[i] = m_points[i] - tangential * (1.0 - m_surface_friction);
            }
        }
        return;
    }

    // Gather each particle's load and the plane it bears on most.
    const bool xpbd = m_contact_compliance > 0.0;
    m_fric_load.assign(count, 0.0);
    m_fric_heaviest.assign(count, 0.0);
    m_fric_normal.resize(count);
    m_fric_touched.clear();
    const auto load_on = [&](int i, const Vector3 &n, double load) {
        if (load <= 0.0 || m_inv_mass[i] == 0.0f)
            return;
        if (m_fric_load[i] == 0.0)
            m_fric_touched.push_back(i);
        if (load > m_fric_heaviest[i])
        {
            m_fric_heaviest[i] = load;
            m_fric_normal[i] = n;
        }
        m_fric_load[i] += load;
    };
    for (int i : m_active_contact)
    {
        const float w = xpbd ? m_inv_mass[i] : 1.0f;
        if (m_c_flags[i] & 1)
            load_on(i, m_c_n1[i], m_contact_lambda_1[i] * w);
        if (m_c_flags[i] & 2)
            load_on(i, m_c_n2[i], m_contact_lambda_2[i] * w);
    }
    // A segment's midpoint contact loads its two ends by their share of the
    // push. Only the share matters here, so the rigid path's larger per-end
    // move (push / weight) is deliberately not reproduced.
    for (int s : m_active_mid)
    {
        for (int slot = 0; slot < 2; ++slot)
        {
            if ((m_mid_contact[s] & (1 << slot)) == 0)
                continue;
            const double lambda = slot == 0 ? m_mid_contact_lambda[s] : m_mid_contact_lambda_2[s];
            if (lambda <= 0.0)
                continue;
            const double t = slot == 0 ? m_mid_contact_t[s] : m_mid_contact_t_2[s];
            const Vector3 &n = slot == 0 ? m_mid_contact_normal[s] : m_mid_contact_normal_2[s];
            if (slot == 0 && (m_mid_contact[s] & 4))
            {
                // An edge bears on ONE point of the segment, anywhere along it,
                // and that point's slide is what the edge resists. Charging
                // each end with a share of the load against its OWN velocity
                // (right for a midpoint lying on a floor) stopped the hanging
                // end of a segment pivoting on a table's edge as if it were
                // the thing touching it.
                const int ia = m_seg_a[s];
                const int ib = m_seg_b[s];
                const double ta = 1.0 - t;
                const double wa = m_inv_mass[ia];
                const double wb = m_inv_mass[ib];
                const double weight = wa * ta * ta + wb * t * t;
                if (weight <= 0.0)
                    continue;
                const Vector3 vel = (m_points[ia] - m_prev_points[ia]) * ta +
                                    (m_points[ib] - m_prev_points[ib]) * t;
                const Vector3 slide = vel - n * vel.dot(n);
                const double len = slide.length();
                if (len <= 1e-12)
                    continue;
                // The multiplier is the push at the contact point per unit of
                // inverse mass there; `weight` turns it into that point's move.
                const double load = xpbd ? lambda * weight : lambda;
                const double share = len <= m_static_friction * load
                                         ? 1.0
                                         : std::min(m_kinetic_friction * load / len, 1.0);
                const Vector3 stop = slide * share;
                m_prev_points[ia] += stop * (wa * ta / weight);
                m_prev_points[ib] += stop * (wb * t / weight);
                continue;
            }
            load_on(m_seg_a[s], n, lambda * (1.0 - t));
            load_on(m_seg_b[s], n, lambda * t);
        }
    }

    for (int i : m_fric_touched)
    {
        const double load = m_fric_load[i];
        const Vector3 n = m_fric_normal[i];
        const Vector3 vel = m_points[i] - m_prev_points[i];
        const Vector3 slide = vel - n * vel.dot(n);
        const double len = slide.length();
        if (len <= 1e-12)
            continue;
        if (len <= m_static_friction * load)
            m_prev_points[i] += slide;
        else
            m_prev_points[i] += slide * std::min(m_kinetic_friction * load / len, 1.0);
    }
}

bool VerletRope::EnvironmentChangedWhileSleeping()
{
    if (m_surface_collision_mask == 0 || m_shape_query.is_null())
        return false;
    Ref<World3D> world = get_world_3d();
    if (world.is_null())
        return false;
    PhysicsDirectSpaceState3D *space_state = world->get_direct_space_state();
    if (space_state == nullptr)
        return false;

    const auto point_inside = [this, space_state](const Vector3 &p) {
        if (m_point_query.is_null())
            return true;
        m_point_query->set_position(p);
        return !space_state->intersect_point(m_point_query, 1).is_empty();
    };
    const auto cached_surface_exists = [this, space_state](const Vector3 &p,
                                                           const Vector3 &cached_p,
                                                           const Vector3 &cached_n) {
        if (m_ray_query.is_null() || cached_n == Vector3())
            return false;
        const double probe = m_collision_radius * 3.0;
        m_ray_query->set_from(p + cached_n * probe);
        m_ray_query->set_to(p - cached_n * probe);
        const Dictionary hit = space_state->intersect_ray(m_ray_query);
        if (hit.is_empty())
            return false;
        const Vector3 n = hit["normal"];
        const Vector3 hp = hit["position"];
        return n.dot(cached_n) > 0.85 &&
               std::abs((hp - cached_p).dot(cached_n)) <= m_collision_radius;
    };

    const int count = static_cast<int>(m_points.size());
    for (int i = 0; i < count; ++i)
    {
        if (m_inv_mass[i] == 0.0f)
            continue;
        // Capsule contacts below are the authoritative support test. Particle
        // planes are only local solver manifold slots and can legitimately go
        // stale as an edge hands support to the adjacent segment. Their one
        // reliable environmental signal is a collider newly covering the
        // stationary centre.
        if (point_inside(m_points[i]))
        {
            const bool cached_valid =
                ((m_c_flags[i] & 1) && PlaneValid(i, m_c_p1[i], m_c_n1[i])) ||
                ((m_c_flags[i] & 2) && PlaneValid(i, m_c_p2[i], m_c_n2[i]));
            if (!cached_valid)
                return true;
        }
    }

    const int seg_count = static_cast<int>(m_seg_a.size());
    for (int s = 0; s < seg_count; ++s)
    {
        const int a = m_seg_a[s];
        const int b = m_seg_b[s];
        if (m_inv_mass[a] + m_inv_mass[b] == 0.0f)
            continue;
        // A segment lying over an EDGE is asked the one thing that can be
        // asked of an edge: is its face still there. The questions below look
        // for a surface along the contact's normal, and an edge contact's
        // normal points out of the CORNER: the face found is turned 45 degrees
        // from it, which read as "the support has changed" on every poll, and
        // a cord left over a table's edge was woken, jolted (20 mm) and slept
        // again about once a second for as long as it lay there.
        if (m_mid_contact[s] & 4)
        {
            if (EdgeStillThere(space_state, s))
                continue;
            return true;
        }
        // A capsule-only hit may lie anywhere along the segment. Poll that
        // cached coordinate, not always the midpoint: on a thin plate the
        // midpoint can be in open air while the segment is legitimately held
        // near one end. Two false midpoint misses used to wake a settled cable,
        // clear its valid manifold and let it fall through the plate.
        const Vector3 sample = (m_mid_contact[s] & 1)
                                   ? m_points[a].lerp(m_points[b], m_mid_contact_t[s])
                                   : (m_points[a] + m_points[b]) * 0.5;
        m_shape_query->set_transform(Transform3D(Basis(), sample));
        const Dictionary rest = space_state->get_rest_info(m_shape_query);
        const bool has = !rest.is_empty() && rest["normal"].operator Vector3() != Vector3();
        const bool had = m_mid_contact[s] != 0;
        if (point_inside(sample) && !had)
            return true;
        if (had)
        {
            if (has)
                continue;
            bool surface_still_there =
                (m_mid_contact[s] & 1) &&
                cached_surface_exists(sample, m_mid_contact_point[s], m_mid_contact_normal[s]);
            if (!surface_still_there && (m_mid_contact[s] & 2))
            {
                const Vector3 sample2 = m_points[a].lerp(m_points[b], m_mid_contact_t_2[s]);
                surface_still_there = cached_surface_exists(
                    sample2, m_mid_contact_point_2[s], m_mid_contact_normal_2[s]);
            }
            if (surface_still_there)
                continue;
            return true;
        }
        (void)has;
    }
    return false;
}

// The surface particle i is resting on, if it is: a cached contact plane it is
// actually touching. Self-collision must not drive such a particle INTO it.
bool VerletRope::RestingNormal(int i, Vector3 &r_normal) const
{
    // Within a radius of touching, not "touching": a strand under another one
    // bobs a millimetre on its surface, and at 5% over the radius that put it in
    // and out of this test on alternate ticks, so the pair shared the push on
    // one tick and the upper strand took all of it on the next, which is what
    // kept it bobbing (a coiled pad cord in the room, 1.5 mm for ever).
    const double touching = m_collision_radius * 2.0;
    if ((m_c_flags[i] & 1) && (m_points[i] - m_c_p1[i]).dot(m_c_n1[i]) <= touching)
    {
        r_normal = m_c_n1[i];
        return true;
    }
    if ((m_c_flags[i] & 2) && (m_points[i] - m_c_p2[i]).dot(m_c_n2[i]) <= touching)
    {
        r_normal = m_c_n2[i];
        return true;
    }
    return false;
}

// Whether a self-collision move `d` on particle i would push it into the surface
// it rests on — by more than a glancing share of the move, so two strands lying
// side by side on a floor still part sideways as they always did.
bool VerletRope::PushesIntoRest(int i, const Vector3 &d) const
{
    Vector3 n;
    if (!RestingNormal(i, n))
        return false;
    const double len = d.length();
    return len > 1e-12 && d.dot(n) < -0.3 * len;
}

// The cord against itself.
//
// Until 2026-11-10 this was one pass AFTER the constraint solve: the eight
// stretch and bend iterations closed a coil with nothing in their way, the pass
// pushed it open again, and a stretch pass after that pulled it part of the
// way shut. A wound-up cord never agreed with itself and churned for as long
// as it was awake (rope_jitter_probe --case=wound: every tick's worst particle
// 10 mm off its path). The contacts are now found once a tick, after the
// integration, and solved INSIDE the loop beside stretch, bend and the
// surfaces, so a coil is a state the solve arrives at.
//
// What a crossing on a surface needs is unchanged:
//   * A strand resting on a surface is never pushed into it: the strand on top
//     takes the whole separation. Split evenly, the lower strand was driven
//     into the floor, the floor threw it back out on the next tick, and a loop
//     unbending across itself popped a strand a full cord's thickness over or
//     under the other in a single tick (rope_crossing_probe: 11-12 mm jumps,
//     and the strands swapped places).
//   * A contact is INELASTIC: parting two strands creates no velocity, and
//     whatever velocity they had toward each other stops (FinishSelfContacts).
//     Left as velocity the push bounced a heap; keeping the approach, strands
//     pressed together were pushed again every tick and a composite lead's
//     breakout knot crept 22 mm across the floor.
//   * Nothing ends a tick inside a surface because of a crossing. That used to
//     be a lift afterwards; the surface planes are solved after the crossings
//     in every iteration now, which is the same thing.
void VerletRope::DetectSelfContacts()
{
    const int count = static_cast<int>(m_points.size());
    const double min_d = m_collision_radius * 2.0;
    // Found a little early: the solve can bring together strands the
    // integration left just apart, and a pair not in the list is not solved.
    const double reach = min_d * 1.25;
    const double reach_sq = reach * reach;
    m_self_moved.assign(count, Vector3());
    const auto add = [&](int a0, int a1, double sa, int b0, int b1, double tb, const Vector3 &n,
                         double clearance) {
        SelfContact c;
        c.a0 = a0;
        c.a1 = a1;
        c.b0 = b0;
        c.b1 = b1;
        c.s = static_cast<float>(sa);
        c.t = static_cast<float>(tb);
        c.normal = n;
        c.clearance = clearance;
        c.pushed = 0.0;
        c.fixed = false;
        // Strand a moves along -n, strand b along +n; an end resting on a
        // surface the move would drive it into holds still.
        c.wa0 = PushesIntoRest(a0, -n) ? 0.0f : m_inv_mass[a0];
        c.wa1 = a1 == a0 ? 0.0f : (PushesIntoRest(a1, -n) ? 0.0f : m_inv_mass[a1]);
        c.wb0 = PushesIntoRest(b0, n) ? 0.0f : m_inv_mass[b0];
        c.wb1 = b1 == b0 ? 0.0f : (PushesIntoRest(b1, n) ? 0.0f : m_inv_mass[b1]);
        const double as0 = 1.0 - sa;
        const double bt0 = 1.0 - tb;
        // A segment that ends at a PIN is the cord entering its plug, and the
        // plug's own body is what is there (the rope has none, so a strand can
        // lie where a plug is). When the strand it meets cannot give way either
        // (it is on the floor), the only thing left to move is the pinned
        // segment's one free end, about the pin: the contact levered it up
        // several millimetres every tick and never got anywhere (a loose plug
        // lying across its own cord in the room: 2-5 mm/tick for ever, and the
        // plug rocked). That pair is left alone.
        const bool a_stuck = c.wa0 == 0.0f && c.wa1 == 0.0f;
        const bool b_stuck = c.wb0 == 0.0f && c.wb1 == 0.0f;
        const bool a_pinned = a1 != a0 && (m_inv_mass[a0] == 0.0f || m_inv_mass[a1] == 0.0f);
        const bool b_pinned = b1 != b0 && (m_inv_mass[b0] == 0.0f || m_inv_mass[b1] == 0.0f);
        if ((a_stuck && b_pinned) || (b_stuck && a_pinned))
            return;
        if (c.wa0 * as0 * as0 + c.wa1 * sa * sa + c.wb0 * bt0 * bt0 + c.wb1 * tb * tb <= 0.0)
        {
            // Both strands are on the surface: neither can give way to it.
            c.wa0 = m_inv_mass[a0];
            c.wa1 = a1 == a0 ? 0.0f : m_inv_mass[a1];
            c.wb0 = m_inv_mass[b0];
            c.wb1 = b1 == b0 ? 0.0f : m_inv_mass[b1];
            if (c.wa0 * as0 * as0 + c.wa1 * sa * sa + c.wb0 * bt0 * bt0 + c.wb1 * tb * tb <= 0.0)
                return;
        }
        const Vector3 va = (m_points[a0] - m_prev_points[a0]) * as0 +
                           (m_points[a1] - m_prev_points[a1]) * sa;
        const Vector3 vb = (m_points[b0] - m_prev_points[b0]) * bt0 +
                           (m_points[b1] - m_prev_points[b1]) * tb;
        c.closing_before = (vb - va).dot(n);
        m_self_contacts.push_back(c);
    };

    for (int i = 0; i < count; ++i)
    {
        const uint8_t g_i = m_self_group[i];
        // j >= i+2 exempts chain neighbours by ARRAY distance, which stops being
        // chain distance once branches are appended: a branch's head and the
        // trunk's end are coincident but far apart in the array, as are the
        // heads of two branches. m_self_group re-states that by construction.
        for (int j = i + 2; j < count; ++j)
        {
            if (m_inv_mass[i] + m_inv_mass[j] == 0.0f)
                continue;
            if (g_i != 0 && g_i == m_self_group[j])
                continue;
            const Vector3 diff = m_points[j] - m_points[i];
            const double d_sq = diff.length_squared();
            if (d_sq >= reach_sq || d_sq < 1e-8)
                continue;
            m_debug_self_pairs += 1;
            add(i, i, 0.0, j, j, 0.0, diff / std::sqrt(d_sq), min_d);
        }
    }

    // Which frayed branch a particle belongs to, or -1 for the trunk.
    const auto branch_of = [this](int i) {
        for (size_t g = 0; g < m_fray.size(); ++g)
            if (i >= m_fray[g].first && i < m_fray[g].first + m_fray[g].count)
                return static_cast<int>(g);
        return -1;
    };

    // Particle pairs do not see two long segments crossing at their middles:
    // every endpoint can be centimetres clear while the rendered tubes pass
    // straight through each other. Work from the real segment table so fray
    // chain boundaries are topological rather than accidental array adjacency.
    const int seg_count = static_cast<int>(m_seg_a.size());
    for (int sa = 0; sa < seg_count; ++sa)
    {
        const int a0 = m_seg_a[sa];
        const int a1 = m_seg_b[sa];
        for (int sb = sa + 1; sb < seg_count; ++sb)
        {
            const int b0 = m_seg_a[sb];
            const int b1 = m_seg_b[sb];
            if (a0 == b0 || a0 == b1 || a1 == b0 || a1 == b1)
                continue; // neighbours joined by construction
            // The first particles around one fray junction deliberately overlap
            // inside the moulded breakout. Preserve the same exemption the point
            // solver uses for that shared construction volume.
            bool construction_pair = false;
            const int ae[2] = {a0, a1};
            const int be[2] = {b0, b1};
            for (int ai = 0; ai < 2 && !construction_pair; ++ai)
                for (int bi = 0; bi < 2; ++bi)
                    if (m_self_group[ae[ai]] != 0 && m_self_group[ae[ai]] == m_self_group[be[bi]])
                    {
                        construction_pair = true;
                        break;
                    }
            if (construction_pair)
                continue;

            const Vector3 p0 = m_points[a0];
            const Vector3 q0 = m_points[b0];
            const Vector3 u = m_points[a1] - p0;
            const Vector3 v = m_points[b1] - q0;
            const Vector3 w = p0 - q0;
            const double uu = u.dot(u);
            const double uv = u.dot(v);
            const double vv = v.dot(v);
            const double uw = u.dot(w);
            const double vw = v.dot(w);
            if (uu < 1e-12 || vv < 1e-12)
                continue;
            // Closest points of the two SEGMENTS, each clamped to its own
            // length. Until 2026-11-10 this took the closest points of the two
            // lines and kept the pair only when both fell inside: the end of
            // one strand sliding sideways into the middle of another was not a
            // contact at all until it had gone through the other's centreline,
            // and then the two were a crossing with nothing to say which was
            // on top, so one was lifted a whole cord's thickness over the other
            // in a single tick (rope_jitter_probe --case=wound: strands lying
            // on the floor jumping 8.5 mm up).
            const double denom = uu * vv - uv * uv;
            double s = denom > 1e-12 ? CLAMP((uv * vw - vv * uw) / denom, 0.0, 1.0) : 0.5;
            double t = (uv * s + vw) / vv;
            if (t < 0.0)
            {
                t = 0.0;
                s = CLAMP(-uw / uu, 0.0, 1.0);
            }
            else if (t > 1.0)
            {
                t = 1.0;
                s = CLAMP((uv - uw) / uu, 0.0, 1.0);
            }
            // End against end is the particle pairs' above.
            const bool s_end = s <= 0.0 || s >= 1.0;
            const bool t_end = t <= 0.0 || t >= 1.0;
            if (s_end && t_end)
                continue;
            // The branches of one breakout leave it side by side, closer than
            // the clearance by construction, and ease apart over the taper.
            // End-against-middle contacts between them there pushed the fan
            // apart for seconds after a composite lead landed, and its plugs
            // crept with it (rope_tests "loose plugs lie still": 164 mm): inside
            // the taper two branches of one end are held apart by their
            // particles alone. Decided by WHERE ALONG THE BRANCH the segments
            // are, never by where on them the closest points fall: the first
            // version asked "is it at an end", and a contact resting just on
            // that line was on one tick and off the next, so a branch lying
            // across another dropped 3.4 mm and was put back every other tick
            // for as long as it lay there (a PS2 A/V lead in the room).
            if (!m_fray.empty())
            {
                const int ba = branch_of(a1);
                const int bb = branch_of(b1);
                if (ba >= 0 && bb >= 0 && ba != bb && m_fray[ba].at_start == m_fray[bb].at_start &&
                    (a1 - m_fray[ba].first < m_fray_taper_segments ||
                     b1 - m_fray[bb].first < m_fray_taper_segments))
                    continue;
            }
            Vector3 diff = (q0 + v * t) - (p0 + u * s);
            const double dist = diff.length();
            if (dist >= reach)
                continue;
            Vector3 n;
            // Two strands a quarter of their clearance apart or less are IN
            // each other, and which way their centrelines happen to be offset
            // says nothing: it is a millimetre of noise that changes sign from
            // one tick to the next. Parted along it, a kink's two segments went
            // straight through each other and back every tick, 6 mm each way,
            // for ever (rope_tests "a swinging cord loses energy"). They are
            // parted along the perpendicular to both instead, on the side the
            // offset leans to if it leans at all, and held to that direction
            // for the whole tick.
            const bool deep = dist <= min_d * 0.25;
            if (!deep)
                n = diff / dist;
            else
            {
                n = u.cross(v);
                if (n.length_squared() < 1e-12)
                {
                    const Vector3 ref = std::abs(u.normalized().dot(Vector3(0, 1, 0))) < 0.9
                                            ? Vector3(0, 1, 0)
                                            : Vector3(1, 0, 0);
                    n = u.cross(ref);
                }
                n = n.normalized();
                if (diff.dot(n) < 0.0)
                    n = -n;
            }
            m_debug_self_segments += 1;
            // A little inside the particles' clearance: two strands lying side
            // by side are held apart by their particles, and correcting the
            // numerical dust between their segments as well kept a draped lead
            // awake indefinitely.
            add(a0, a1, s, b0, b1, t, n, min_d * 0.92);
            if (deep && !m_self_contacts.empty())
                m_self_contacts.back().fixed = true;
        }
    }
}


inline void VerletRope::SolveSelfContacts()
{
    for (SelfContact &c : m_self_contacts)
    {
        const double s = c.s;
        const double t = c.t;
        const double as0 = 1.0 - s;
        const double bt0 = 1.0 - t;
        const Vector3 pa = m_points[c.a0] * as0 + m_points[c.a1] * s;
        const Vector3 pb = m_points[c.b0] * bt0 + m_points[c.b1] * t;
        const Vector3 diff = pb - pa;
        double dist = diff.length();
        if (dist >= c.clearance)
            continue;
        Vector3 n = dist > c.clearance * 0.01 ? diff / dist : c.normal;
        // The side each strand is on was settled when the contact was found.
        // If an earlier constraint in this pass has carried one THROUGH the
        // other, parting them along where they are now finishes the swap;
        // take them back the way they came instead.
        if (c.fixed || n.dot(c.normal) < 0.0)
        {
            n = c.normal;
            dist = diff.dot(n);
            if (dist >= c.clearance)
                continue;
        }
        const double weight = c.wa0 * as0 * as0 + c.wa1 * s * s + c.wb0 * bt0 * bt0 + c.wb1 * t * t;
        const double lambda = (c.clearance - dist) / weight;
        c.pushed += c.clearance - dist;
        const Vector3 da0 = n * (-lambda * c.wa0 * as0);
        const Vector3 db0 = n * (lambda * c.wb0 * bt0);
        m_points[c.a0] += da0;
        m_points[c.b0] += db0;
        m_self_moved[c.a0] += da0;
        m_self_moved[c.b0] += db0;
        if (c.a1 != c.a0)
        {
            const Vector3 da1 = n * (-lambda * c.wa1 * s);
            m_points[c.a1] += da1;
            m_self_moved[c.a1] += da1;
        }
        if (c.b1 != c.b0)
        {
            const Vector3 db1 = n * (lambda * c.wb1 * t);
            m_points[c.b1] += db1;
            m_self_moved[c.b1] += db1;
        }
    }
}


// After the solve, on VELOCITY: a strand contact neither bounces nor keeps
// closing. Every particle's history moves with whatever the contacts pushed
// it (all of it, not only the part along a contact's normal: a segment lying
// across another strand was otherwise left ROCKING on it, one end up 2 mm and
// the other down, the other way round the next tick, which is a motion the
// contact point itself has no part in), and then any approach still left
// between two touching points is stopped.
void VerletRope::FinishSelfContacts()
{
    if (m_self_contacts.empty())
        return;
    for (size_t i = 0; i < m_self_moved.size(); ++i)
        m_prev_points[i] += m_self_moved[i];
    for (const SelfContact &c : m_self_contacts)
    {
        if (c.pushed <= 0.0)
            continue;
        const double s = c.s;
        const double t = c.t;
        const double as0 = 1.0 - s;
        const double bt0 = 1.0 - t;
        const Vector3 pa = m_points[c.a0] * as0 + m_points[c.a1] * s;
        const Vector3 pb = m_points[c.b0] * bt0 + m_points[c.b1] * t;
        const Vector3 diff = pb - pa;
        const double dist = diff.length();
        const Vector3 n = dist > c.clearance * 0.01 ? diff / dist : c.normal;
        const Vector3 va = (m_points[c.a0] - m_prev_points[c.a0]) * as0 +
                           (m_points[c.a1] - m_prev_points[c.a1]) * s;
        const Vector3 vb = (m_points[c.b0] - m_prev_points[c.b0]) * bt0 +
                           (m_points[c.b1] - m_prev_points[c.b1]) * t;
        const double parting = (vb - va).dot(n);
        // Parting velocity is theirs to keep (a hand lifting one strand off
        // the other); an approach is not.
        const double wanted = std::max(parting, 0.0);
        const double weight = c.wa0 * as0 * as0 + c.wa1 * s * s + c.wb0 * bt0 * bt0 + c.wb1 * t * t;
        // Velocity lives in the history: to change a point's velocity by dv,
        // move its previous position by -dv.
        Vector3 dv = n * ((wanted - parting) / weight);
        // Strand on strand grips as strand on surface does, by the same rule
        // and on velocity only (see ApplyContactFriction): the load is how far
        // the solve had to part the two this step. With none, a strand lying
        // ON another skated from side to side across it for as long as the
        // cord was awake, and a pile slumped.
        const Vector3 slide = (vb - va) - n * parting;
        const double len = slide.length();
        if (len > 1e-12 && (m_debug_disable & 2) == 0 &&
            (m_static_friction > 0.0 || m_kinetic_friction > 0.0))
        {
            const double share = len <= m_static_friction * c.pushed
                                     ? 1.0
                                     : std::min(m_kinetic_friction * c.pushed / len, 1.0);
            dv -= slide * (share / weight);
        }
        m_prev_points[c.a0] += dv * (c.wa0 * as0);
        m_prev_points[c.b0] -= dv * (c.wb0 * bt0);
        if (c.a1 != c.a0)
            m_prev_points[c.a1] += dv * (c.wa1 * s);
        if (c.b1 != c.b0)
            m_prev_points[c.b1] -= dv * (c.wb1 * t);
    }
}


// Which slot a freshly reported plane belongs in. The cascade is ordered by how
// much the new normal agrees with what is already cached: an almost-exact match
// refreshes that slot, a loose match (a cord sliding over a curved surface)
// still refreshes it rather than banking a second nearly-parallel plane, which
// would pinch the particle as if the smooth pipe were a sharp corner. Only once
// neither cached plane can claim it does an empty slot take it.
//
// Returning 0 is a real outcome, not a fallthrough: when BOTH slots are valid
// and neither normal matches, the stable two-plane manifold of a genuine edge
// is kept and the new plane is dropped.
int VerletRope::ChooseContactSlot(int i, const Vector3 &p_point, const Vector3 &p_normal,
                                  bool p_keep1, bool p_keep2) const
{
    const double d1 = p_normal.dot(m_c_n1[i]);
    const double d2 = p_normal.dot(m_c_n2[i]);
    if (p_keep1 && d1 > 0.9)
        return 1;
    if (p_keep2 && d2 > 0.9)
        return 2;
    if (p_keep1 && d1 > 0.5)
        return 1;
    if (p_keep2 && d2 > 0.5)
        return 2;
    if (!p_keep1)
        return 1;
    if (!p_keep2)
    {
        // A second plane is for a real edge, so it has to be near the first.
        // A distant one is a different surface: overwrite slot 1 instead of
        // banking a manifold spanning two places the cord cannot touch at once.
        return p_point.distance_to(m_c_p1[i]) < m_collision_radius * 3.0 ? 2 : 1;
    }
    return 0;
}


// Write a plane into a slot. Occupying a slot always validates it, including
// the arms that overwrite one that was already valid.
void VerletRope::AssignContactSlot(int i, int p_slot, const Vector3 &p_point,
                                   const Vector3 &p_normal, bool &r_keep1, bool &r_keep2)
{
    if (p_slot == 1)
    {
        m_c_p1[i] = p_point;
        m_c_n1[i] = p_normal;
        r_keep1 = true;
    }
    else if (p_slot == 2)
    {
        m_c_p2[i] = p_point;
        m_c_n2[i] = p_normal;
        r_keep2 = true;
    }
}


void VerletRope::SolveSurfaceCollision(bool p_do_rest)
{
    Ref<World3D> world = get_world_3d();
    if (world.is_null())
        return;
    PhysicsDirectSpaceState3D *space_state = world->get_direct_space_state();
    if (space_state == nullptr)
        return;

    SweepParticleContacts(space_state, p_do_rest);
    SolveSegmentCollision(space_state, p_do_rest);
    if (p_do_rest)
        RecoverWrongSideParticles(space_state);
}


// ── Edge contacts ───────────────────────────────────────────────────────────
// A chain of straight segments cannot follow a sharp corner with its particles
// alone: each particle that passes the edge loses the face it stood on, and the
// segment behind it has to PIVOT on the edge while it goes round. A plane cached
// at a fixed place along the segment cannot say that (the contact slides along
// the segment as the cord is pulled), so a cord dragged over a table's corner
// dropped a particle 6-13 mm each time one went over (rope_jitter_probe
// --case=corner). An edge contact keeps the edge's LINE instead, and slot 1 of
// the segment's contact is re-derived from it every tick: the point of the
// segment nearest the line must stay one radius clear of it, along the
// perpendicular from the line. As that point nears an end of the segment the
// next segment along is given the line TOO: with a particle at the edge both of
// its segments bear on it, and passing one contact back and forth between them
// (the first version) left one of the two inside the corner on every tick.

// Where along segment s its line comes nearest the edge line, unclamped.
// False when the two are parallel (any point of the segment is as near).
bool VerletRope::EdgeParam(int s, const Vector3 &p_point, const Vector3 &p_dir, double &r_t) const
{
    const Vector3 a = m_points[m_seg_a[s]];
    const Vector3 d = m_points[m_seg_b[s]] - a;
    const Vector3 w0 = a - p_point;
    const double dd = d.dot(d);
    const double de = d.dot(p_dir);
    const double denom = dd - de * de;
    if (denom < dd * 1e-6 || dd < 1e-12)
    {
        r_t = 0.5;
        return false;
    }
    r_t = (de * static_cast<double>(p_dir.dot(w0)) - static_cast<double>(d.dot(w0))) / denom;
    return true;
}


// Re-derive slot 1 of segment s's contact from its edge line. False when the
// nearest point has run off the segment, or the segment has lifted clear.
bool VerletRope::PlaceEdgeContact(int s)
{
    const Vector3 &x = m_edge_point[s];
    const Vector3 &e = m_edge_dir[s];
    double raw = 0.5;
    EdgeParam(s, x, e, raw);
    const double t = CLAMP(raw, 0.0, 1.0);
    const Vector3 a = m_points[m_seg_a[s]];
    const Vector3 d = m_points[m_seg_b[s]] - a;
    const Vector3 sample = a + d * t;
    const Vector3 on_edge = x + e * (sample - x).dot(e);
    const Vector3 w = sample - on_edge;
    const double dist = w.length();
    const Vector3 bisector = (m_edge_n1[s] + m_edge_n2[s]).normalized();
    Vector3 n;
    if (w.dot(m_edge_n1[s]) < 0.0 && w.dot(m_edge_n2[s]) < 0.0)
    {
        // The centreline is inside the corner: out along the perpendicular to
        // both the edge and the segment, on the open side. At an END of the
        // segment that perpendicular is the segment's own business and its
        // neighbour's differs, so there it is the corner's bisector for both.
        n = e.cross(d);
        if (raw != t || n.length_squared() < 1e-12)
            n = bisector;
        else
        {
            n = n.normalized();
            if (n.dot(bisector) < 0.0)
                n = -n;
        }
    }
    else if (dist > 1e-6)
    {
        n = w / dist;
        if (dist > m_collision_radius * 3.0)
            return false;
    }
    else
        n = bisector;
    m_mid_contact[s] = 1 | 4;
    m_mid_contact_point[s] = on_edge;
    m_mid_contact_normal[s] = n;
    m_mid_contact_t[s] = static_cast<float>(t);
    return true;
}


void VerletRope::UpdateEdgeContacts()
{
    const int seg_count = static_cast<int>(m_seg_a.size());
    for (int s = 0; s < seg_count; ++s)
    {
        if ((m_mid_contact[s] & 4) == 0)
            continue;
        if (!PlaceEdgeContact(s))
        {
            // Lifted clear, or slid so far along that no part of it is near.
            m_mid_contact[s] = 0;
            m_debug_edges_lost += 1;
            continue;
        }
        // The edge is where its two faces END. A plane cached from one of them
        // holds a particle only on that face's side of the other: past it the
        // plane is standing in the air (a particle hauled up over a table's
        // edge was stopped for three ticks by the side face's plane, which
        // goes on up for ever, until the rest pass let it go). Known exactly
        // here, so it is said every tick, not found out by a ray every third.
        const int ends[2] = {m_seg_a[s], m_seg_b[s]};
        for (int i : ends)
        {
            if (m_c_flags[i] == 0)
                continue;
            const Vector3 off = m_points[i] - m_edge_point[s];
            const double past1 = off.dot(m_edge_n1[s]);
            const double past2 = off.dot(m_edge_n2[s]);
            for (int slot = 0; slot < 2; ++slot)
            {
                if ((m_c_flags[i] & (1 << slot)) == 0)
                    continue;
                const Vector3 &n = slot == 0 ? m_c_n1[i] : m_c_n2[i];
                if ((n.dot(m_edge_n1[s]) > 0.95 && past2 > 0.0) ||
                    (n.dot(m_edge_n2[s]) > 0.95 && past1 > 0.0))
                    m_c_flags[i] &= static_cast<uint8_t>(~(1 << slot));
            }
        }
        double raw = 0.5;
        EdgeParam(s, m_edge_point[s], m_edge_dir[s], raw);
        const int other = raw > 0.8 ? m_next_seg[m_seg_b[s]] : (raw < 0.2 ? m_prev_seg[m_seg_a[s]] : -1);
        if (other < 0 || other == s || (m_mid_contact[other] & 4) != 0 ||
            m_inv_mass[m_seg_a[other]] + m_inv_mass[m_seg_b[other]] == 0.0f)
            continue;
        const uint8_t was = m_mid_contact[other];
        const Vector3 was_point = m_mid_contact_point[other];
        const Vector3 was_normal = m_mid_contact_normal[other];
        const float was_t = m_mid_contact_t[other];
        m_edge_point[other] = m_edge_point[s];
        m_edge_dir[other] = m_edge_dir[s];
        m_edge_n1[other] = m_edge_n1[s];
        m_edge_n2[other] = m_edge_n2[s];
        if (PlaceEdgeContact(other))
            m_debug_edge_handovers += 1;
        else
        {
            m_mid_contact[other] = was;
            m_mid_contact_point[other] = was_point;
            m_mid_contact_normal[other] = was_normal;
            m_mid_contact_t[other] = was_t;
        }
    }
}


// Particle i has run off the face whose plane it held (p_point, p_normal). Look
// back under that face from where the particle is now: the face met there is
// the other side of the edge the cord has gone over. Whichever segment at i
// crosses the edge gets it.
void VerletRope::FindEdgeFor(PhysicsDirectSpaceState3D *space_state, int i, const Vector3 &p_point,
                             const Vector3 &p_normal)
{
    if (m_debug_disable & 1)
        return;
    const double under = m_collision_radius * 0.5;
    const double d = (m_points[i] - p_point).dot(p_normal);
    const Vector3 from = m_points[i] - p_normal * (d + under);
    Vector3 to = p_point - p_normal * under;
    const Vector3 along = to - from;
    if (along.length_squared() < 1e-10)
        return;
    to += along.normalized() * m_collision_radius;
    m_ray_query->set_from(from);
    m_ray_query->set_to(to);
    const Dictionary hit = space_state->intersect_ray(m_ray_query);
    if (hit.is_empty())
        return;
    const Vector3 n2 = hit["normal"];
    const Vector3 p2 = hit["position"];
    Vector3 e = p_normal.cross(n2);
    if (n2 == Vector3() || e.length_squared() < 0.09)
        return; // the same face again, or its back: not a corner
    e = e.normalized();
    // A point on both planes: from the hit, in the second face, to the first.
    const Vector3 u = e.cross(n2);
    const double denom = u.dot(p_normal);
    if (std::abs(denom) < 1e-6)
        return;
    const Vector3 x = p2 + u * ((p_point - p2).dot(p_normal) / denom);
    const int candidates[2] = {m_prev_seg[i], m_next_seg[i]};
    for (int s : candidates)
    {
        if (s < 0 || (m_mid_contact[s] & 4) != 0 ||
            m_inv_mass[m_seg_a[s]] + m_inv_mass[m_seg_b[s]] == 0.0f)
            continue;
        const uint8_t was = m_mid_contact[s];
        m_edge_point[s] = x;
        m_edge_dir[s] = e;
        m_edge_n1[s] = p_normal;
        m_edge_n2[s] = n2;
        if (PlaceEdgeContact(s))
        {
            m_debug_edges_found += 1;
            return;
        }
        m_mid_contact[s] = was;
    }
}


// Whether the first face of segment s's edge is still where it was, read just
// inside the edge under the contact (a ray AT an edge is a coin toss).
bool VerletRope::EdgeStillThere(PhysicsDirectSpaceState3D *space_state, int s)
{
    const Vector3 &n1 = m_edge_n1[s];
    Vector3 inward = m_edge_dir[s].cross(n1);
    if (inward.dot(m_edge_n2[s]) > 0.0)
        inward = -inward;
    const Vector3 on_face = m_mid_contact_point[s] + inward * (m_collision_radius * 0.5);
    Vector3 point = on_face;
    Vector3 normal = n1;
    if (!SurfaceUnder(space_state, on_face + n1 * m_collision_radius, m_collision_radius * 2.0,
                      point, normal))
        return false;
    return normal.dot(n1) > 0.98 && std::abs((point - on_face).dot(n1)) < m_collision_radius * 0.25;
}


// The front face met by a ray from `p_from` along -r_normal within `p_reach`,
// if it faces the way r_normal does: its point and its own normal come back in
// the two references.
bool VerletRope::SurfaceUnder(PhysicsDirectSpaceState3D *space_state, const Vector3 &p_from,
                              double p_reach, Vector3 &r_point, Vector3 &r_normal)
{
    m_ray_query->set_from(p_from);
    m_ray_query->set_to(p_from - r_normal * p_reach);
    const Dictionary hit = space_state->intersect_ray(m_ray_query);
    if (hit.is_empty())
        return false;
    const Vector3 n = hit["normal"];
    if (n == Vector3() || n.dot(r_normal) < 0.7)
        return false;
    r_point = hit["position"];
    r_normal = n;
    return true;
}


// Whether the surface a cached plane was read from is still under particle i,
// re-reading the plane from it when it is (a curved surface turns under a cord).
bool VerletRope::PlaneSupported(PhysicsDirectSpaceState3D *space_state, int i, Vector3 &r_point,
                                Vector3 &r_normal)
{
    if (m_debug_disable & 4)
        return true;
    // From no lower than the resting height, so a particle the solve has left
    // pressed into the surface still finds its face from the front.
    const double d = (m_points[i] - r_point).dot(r_normal);
    const double lift = std::max(0.0, m_collision_radius - d);
    Vector3 point = r_point;
    Vector3 normal = r_normal;
    if (!SurfaceUnder(space_state, m_points[i] + r_normal * lift,
                      lift + std::max(d, 0.0) + m_collision_radius, point, normal))
        return false;
    r_point = point;
    r_normal = normal;
    return true;
}


// Phase one: each particle's own motion sweep, and its cached contact planes.
void VerletRope::SweepParticleContacts(PhysicsDirectSpaceState3D *space_state, bool p_do_rest)
{
    const int count = static_cast<int>(m_points.size());
    const bool swept = m_substeps > 1 && m_tick_from.size() == m_points.size();
    for (int i = 0; i < count; ++i)
    {
        if (m_inv_mass[i] == 0.0f)
            continue;
        // Sweep this frame's motion so a point can't tunnel through thin
        // geometry, even between rest-query frames.
        const Vector3 from = swept ? m_tick_from[i] : m_prev_points[i];
        const Vector3 to = m_points[i];
        const Vector3 motion = to - from;
        if (motion.length_squared() > 0.000001)
        {
            m_ray_query->set_from(from);
            m_ray_query->set_to(to + motion.normalized() * m_collision_radius);
            Dictionary hit = space_state->intersect_ray(m_ray_query);
            if (!hit.is_empty())
            {
                const Vector3 hit_normal = hit["normal"];
                if (hit_normal != Vector3())
                {
                    const Vector3 hit_point = hit["position"];
                    const double length = motion.length();
                    bool keep1 = (m_c_flags[i] & 1) != 0 && PlaneValid(i, m_c_p1[i], m_c_n1[i]);
                    bool keep2 = (m_c_flags[i] & 2) != 0 && PlaneValid(i, m_c_p2[i], m_c_n2[i]);
                    int slot = ChooseContactSlot(i, hit_point, hit_normal, keep1, keep2);
                    if ((hit_point - from).dot(motion) <= length * length)
                    {
                        // The centre really crossed the surface this tick: stop
                        // it where it went in. This plane is not optional, so it
                        // takes slot 1 even from a full manifold.
                        ResolveContact(i, hit_point, hit_normal);
                        m_debug_sweep_snaps += 1;
                        if (slot == 0)
                            slot = 1;
                    }
                    else
                    {
                        // The ray reaches one radius PAST the particle, so this
                        // hit is ahead of it: the jacket is about to touch, the
                        // centre has crossed nothing. Snapping to the hit point
                        // here carried the particle up to a radius along its own
                        // motion and cut its slide by surface_friction, on any
                        // tick a resting particle moved a millimetre with the
                        // slightest lean into its surface (a cord dragged round
                        // a table corner: 14 mm kicks). Hold it off the plane
                        // where it IS, without making or keeping velocity into
                        // the surface, and let the solve own the contact.
                        const double depth = m_collision_radius - (to - hit_point).dot(hit_normal);
                        if (depth > 0.0)
                        {
                            const double inward = std::min(
                                0.0, static_cast<double>((to - m_prev_points[i]).dot(hit_normal)));
                            m_points[i] += hit_normal * depth;
                            m_prev_points[i] += hit_normal * (depth + inward);
                        }
                    }
                    AssignContactSlot(i, slot, hit_point, hit_normal, keep1, keep2);
                    m_c_flags[i] = static_cast<uint8_t>((keep1 ? 1 : 0) | (keep2 ? 2 : 0));
                    continue;
                }
            }
        }
        // Resting contact (throttled — heavier query): refresh the particle's
        // cached contact-plane manifold. The planes are enforced every frame
        // INSIDE the constraint loop, so contacts are part of the solver's
        // equilibrium; snapping the particle here instead fights the other
        // constraints and jitters edge wraps. The query only reports the deepest
        // plane (which alternates at a corner), so a still-valid previous plane
        // with a different normal is kept as a second slot.
        if (p_do_rest)
        {
            m_shape_query->set_transform(Transform3D(Basis(), m_points[i]));
            Dictionary rest = space_state->get_rest_info(m_shape_query);
            bool keep1 = (m_c_flags[i] & 1) != 0 && PlaneValid(i, m_c_p1[i], m_c_n1[i]);
            bool keep2 = (m_c_flags[i] & 2) != 0 && PlaneValid(i, m_c_p2[i], m_c_n2[i]);
            // Deep-penetration guard: if the particle centre is BEHIND the
            // reported plane it has passed the surface, and ejecting along this
            // normal can pop it out the FAR side of a slab. Don't cache — the
            // wrong-side recovery below walks it back instead.
            int fresh = 0;
            if (!rest.is_empty())
            {
                Vector3 nn = rest["normal"];
                Vector3 np = rest["point"];
                // The sphere only says which WAY the nearest surface lies; the
                // surface itself is read with a ray, as the sweep reads it. The
                // two do not agree near a box's edge (Jolt rounds a box by its
                // margin for shape queries, up to 4 cm, and a ray sees it
                // sharp), and a particle fed planes from both was thrown from
                // one to the other.
                // When the sphere reports the very plane a slot already holds,
                // that IS the surface under the particle, read by a ray once
                // already: no second ray (most of a cord lying on a floor).
                const double same = m_collision_radius * 0.1;
                if (keep1 && nn.dot(m_c_n1[i]) > 0.999 &&
                    std::abs((np - m_c_p1[i]).dot(m_c_n1[i])) < same)
                    fresh = 1;
                else if (keep2 && nn.dot(m_c_n2[i]) > 0.999 &&
                         std::abs((np - m_c_p2[i]).dot(m_c_n2[i])) < same)
                    fresh = 2;
                else if (nn != Vector3() && (m_points[i] - np).dot(nn) >= 0.0 &&
                    ((m_debug_disable & 4) ||
                     SurfaceUnder(space_state, m_points[i], m_collision_radius * 1.5, np, nn)))
                {
                    fresh = ChooseContactSlot(i, np, nn, keep1, keep2);
                    AssignContactSlot(i, fresh, np, nn, keep1, keep2);
                }
            }
            // A cached plane is infinite; the face it came from is not. Keep a
            // plane only while there is surface under the particle: one that had
            // slid off a table's edge used to stand on the table top's plane in
            // mid air, stuck there by static friction, until it was 6 cm from
            // where it last touched, and then dropped 13 mm in a tick.
            // The face a particle has just run off ends in an edge, and the
            // cord is now lying over it: hand that edge to the segment.
            if (keep1 && fresh != 1 && !PlaneSupported(space_state, i, m_c_p1[i], m_c_n1[i]))
            {
                keep1 = false;
                FindEdgeFor(space_state, i, m_c_p1[i], m_c_n1[i]);
            }
            if (keep2 && fresh != 2 && !PlaneSupported(space_state, i, m_c_p2[i], m_c_n2[i]))
            {
                keep2 = false;
                FindEdgeFor(space_state, i, m_c_p2[i], m_c_n2[i]);
            }
            m_c_flags[i] = static_cast<uint8_t>((keep1 ? 1 : 0) | (keep2 ? 2 : 0));
        }
    }

}


// Phase two: whole-segment capsule collision. Point rays miss an obstacle
// whenever both particles clear it but the jacket between them does not.
// Translation is swept every tick; the final, rotated capsule is sampled on the
// resting contact cadence. The resulting point along the segment is constrained
// in the same iterative solve as stretch and bend.
void VerletRope::SolveSegmentCollision(PhysicsDirectSpaceState3D *space_state, bool p_do_rest)
{
    const int seg_count = static_cast<int>(m_seg_a.size());
    const bool swept = m_substeps > 1 && m_tick_from.size() == m_points.size();
    const auto set_capsule = [&](const Vector3 &a, const Vector3 &b) {
        const Vector3 segment = b - a;
        const double length = segment.length();
        Basis basis;
        if (length > 1e-8)
            basis = Basis(Quaternion(Vector3(0, 1, 0), segment / length));
        m_segment_capsule->set_height(static_cast<float>(length + m_collision_radius * 2.6));
        return Transform3D(basis, (a + b) * 0.5);
    };
    const auto cache_segment_hit = [&](int s, const Dictionary &rest) {
        if (rest.is_empty())
            return false;
        const Vector3 n = rest["normal"];
        if (n == Vector3())
            return false;
        const int ia = m_seg_a[s];
        const int ib = m_seg_b[s];
        const Vector3 segment = m_points[ib] - m_points[ia];
        const double length_sq = segment.length_squared();
        const Vector3 point = rest["point"];
        double t = length_sq > 1e-10
                       ? CLAMP((point - m_points[ia]).dot(segment) / length_sq, 0.0, 1.0)
                       : 0.5;
        const auto slot_valid = [&](bool second) {
            const float old_t = second ? m_mid_contact_t_2[s] : m_mid_contact_t[s];
            const Vector3 &old_point = second ? m_mid_contact_point_2[s] : m_mid_contact_point[s];
            const Vector3 &old_normal = second ? m_mid_contact_normal_2[s] : m_mid_contact_normal[s];
            const Vector3 old_sample = m_points[ia].lerp(m_points[ib], old_t);
            return old_sample.distance_squared_to(old_point) <=
                       m_seg_rest[s] * m_seg_rest[s] * 4.0 &&
                   std::abs((old_sample - old_point).dot(old_normal)) <
                       m_collision_radius * 3.0;
        };
        if ((m_mid_contact[s] & 1) && !slot_valid(false))
            m_mid_contact[s] &= ~1;
        if ((m_mid_contact[s] & 2) && !slot_valid(true))
            m_mid_contact[s] &= ~2;

        bool second = false;
        if ((m_mid_contact[s] & 1) && n.dot(m_mid_contact_normal[s]) > 0.9)
            t = m_mid_contact_t[s];
        else if ((m_mid_contact[s] & 2) && n.dot(m_mid_contact_normal_2[s]) > 0.9)
        {
            second = true;
            t = m_mid_contact_t_2[s];
        }
        else if ((m_mid_contact[s] & 1) == 0)
            second = false;
        else if ((m_mid_contact[s] & 2) == 0)
        {
            // Two simultaneous planes are for a real sharp edge. A curved pipe
            // also changes normal as the contact coordinate slides, but keeping
            // both nearby tangents pinches the segment and creates chatter.
            second = std::abs(n.dot(m_mid_contact_normal[s])) < 0.2 &&
                     point.distance_to(m_mid_contact_point[s]) < m_collision_radius;
        }
        else
            return true; // both edge faces remain valid; keep the stable manifold

        const Vector3 centreline = m_points[ia].lerp(m_points[ib], t);
        if (-(centreline - point).dot(n) > m_collision_radius * 3.0)
            return false;
        if (second)
        {
            m_mid_contact[s] |= 2;
            m_mid_contact_point_2[s] = point;
            m_mid_contact_normal_2[s] = n;
            m_mid_contact_t_2[s] = static_cast<float>(t);
        }
        else
        {
            m_mid_contact[s] |= 1;
            m_mid_contact_point[s] = point;
            m_mid_contact_normal[s] = n;
            m_mid_contact_t[s] = static_cast<float>(t);
        }
        return true;
    };
    for (int s = 0; s < seg_count; ++s)
    {
        const int ia = m_seg_a[s];
        const int ib = m_seg_b[s];
        if (m_inv_mass[ia] + m_inv_mass[ib] == 0.0f)
            continue;
        const Vector3 from_a = swept ? m_tick_from[ia] : m_prev_points[ia];
        const Vector3 from_b = swept ? m_tick_from[ib] : m_prev_points[ib];
        const Vector3 previous_mid = (from_a + from_b) * 0.5;
        const Vector3 current_mid = (m_points[ia] + m_points[ib]) * 0.5;
        const Vector3 motion = current_mid - previous_mid;
        const double capsule_sweep_threshold = m_collision_radius * 4.0;
        if (m_mid_contact[s] == 0 &&
            motion.length_squared() > capsule_sweep_threshold * capsule_sweep_threshold)
        {
            m_segment_shape_query->set_transform(set_capsule(from_a, from_b));
            m_segment_shape_query->set_motion(Vector3());
            const bool already_touching =
                !space_state->get_rest_info(m_segment_shape_query).is_empty();
            if (!already_touching)
            {
                m_segment_shape_query->set_motion(motion);
                const PackedFloat32Array fractions = space_state->cast_motion(m_segment_shape_query);
                if (fractions.size() >= 2 && fractions[0] < 1.0f)
                {
                    const double safe = fractions[0];
                    const double unsafe = fractions[1];
                    const Vector3 wanted_a = m_points[ia];
                    const Vector3 wanted_b = m_points[ib];
                    const Vector3 hit_a = from_a.lerp(wanted_a, unsafe);
                    const Vector3 hit_b = from_b.lerp(wanted_b, unsafe);
                    m_segment_shape_query->set_transform(set_capsule(hit_a, hit_b));
                    m_segment_shape_query->set_motion(Vector3());
                    Dictionary hit = space_state->get_rest_info(m_segment_shape_query);
                    if (!hit.is_empty() && hit["normal"].operator Vector3() != Vector3())
                    {
                        const Vector3 hit_segment = hit_b - hit_a;
                        const double hit_length_sq = hit_segment.length_squared();
                        const Vector3 hit_point = hit["point"];
                        const double t = hit_length_sq > 1e-10
                                             ? CLAMP((hit_point - hit_a).dot(hit_segment) /
                                                         hit_length_sq,
                                                     0.0, 1.0)
                                             : 0.5;
                        const Vector3 safe_a = from_a.lerp(wanted_a, safe);
                        const Vector3 safe_b = from_b.lerp(wanted_b, safe);
                        const Vector3 correction = safe_a.lerp(safe_b, t) -
                                                   wanted_a.lerp(wanted_b, t);
                        const double ta = 1.0 - t;
                        const double weight = m_inv_mass[ia] * ta * ta +
                                              m_inv_mass[ib] * t * t;
                        if (weight > 0.0)
                        {
                            const Vector3 da = correction * (m_inv_mass[ia] * ta / weight);
                            const Vector3 db = correction * (m_inv_mass[ib] * t / weight);
                            m_points[ia] += da;
                            m_points[ib] += db;
                            m_prev_points[ia] += da;
                            m_prev_points[ib] += db;
                            // Zero the contact point's inward normal velocity.
                            // Preserving it makes the same swept segment strike
                            // the edge again next tick and pumps a pendulum mode.
                            const Vector3 normal = hit["normal"];
                            const Vector3 contact_velocity =
                                m_points[ia].lerp(m_points[ib], t) -
                                m_prev_points[ia].lerp(m_prev_points[ib], t);
                            const double normal_velocity = contact_velocity.dot(normal);
                            if (normal_velocity < 0.0)
                            {
                                const Vector3 stop = normal * normal_velocity;
                                m_prev_points[ia] += stop * (m_inv_mass[ia] * ta / weight);
                                m_prev_points[ib] += stop * (m_inv_mass[ib] * t / weight);
                            }
                        }
                        cache_segment_hit(s, hit);
                        m_debug_capsule_stops += 1;
                    }
                }
            }
        }
        if (p_do_rest && (m_mid_contact[s] & 4))
        {
            // An edge contact is re-derived from its line every tick. All the
            // rest pass has to ask is whether the edge is still there.
            if (!EdgeStillThere(space_state, s))
            {
                m_mid_contact[s] = 0;
                m_debug_edges_lost += 1;
            }
        }
        else if (p_do_rest)
        {
            // Prefer the finite midpoint sphere on broad resting surfaces: a
            // full capsule has infinitely many equally deep contacts there and
            // the engine may hand back a different coordinate every refresh.
            // Fall back to the capsule only for its actual blind spot — an
            // obstacle intersecting the segment away from its midpoint.
            const Vector3 midpoint = (m_points[ia] + m_points[ib]) * 0.5;
            m_shape_query->set_transform(Transform3D(Basis(), midpoint));
            const Dictionary midpoint_rest = space_state->get_rest_info(m_shape_query);
            if (!midpoint_rest.is_empty())
            {
                // A finite midpoint sphere owns one contact coordinate. Replace
                // its plane as a smooth surface turns; two planes here would
                // pinch a cord on a pipe. The two-slot manifold is reserved for
                // capsule-only edge contacts away from the midpoint.
                if ((m_mid_contact[s] & 1) &&
                    m_mid_contact_normal[s].dot(midpoint_rest["normal"].operator Vector3()) < 0.9)
                    m_debug_mid_turns += 1;
                m_mid_contact[s] = 0;
                if (cache_segment_hit(s, midpoint_rest))
                    m_mid_contact_t[s] = 0.5f;
            }
            else
            {
                m_segment_shape_query->set_transform(set_capsule(m_points[ia], m_points[ib]));
                m_segment_shape_query->set_motion(Vector3());
                if (!cache_segment_hit(s, space_state->get_rest_info(m_segment_shape_query)))
                    m_mid_contact[s] = 0;
            }
        }
    }

}


// Phase three: wrong-side recovery. A particle that tunnelled through a slab
// gets locked on the far side — every time the stretch constraints pull it
// back, the motion sweep hits the slab's far face front-on and re-strands it,
// so the state is self-sustaining. Local contact info can't detect this;
// CONNECTIVITY can: cast the segment ray BOTH ways. A segment genuinely
// passing through a slab enters one face and exits through an opposing face
// (normals antiparallel), while a legit drape over an edge crosses roughly
// perpendicular faces. Require the state on two consecutive rest passes, then
// teleport the particle back to the entry face.
//
// Rest passes only — the caller gates it.
void VerletRope::RecoverWrongSideParticles(PhysicsDirectSpaceState3D *space_state)
{
    const int seg_count = static_cast<int>(m_seg_a.size());
    for (int s = 0; s < seg_count; ++s)
    {
        const int prev = m_seg_a[s];
        const int i = m_seg_b[s];
        if (m_inv_mass[i] == 0.0f)
            continue;
        const Vector3 seg_vec = m_points[i] - m_points[prev];
        const double seg_len = seg_vec.length();
        if (seg_len < 0.0001)
        {
            m_stuck_passes[i] = 0;
            continue;
        }
        m_ray_query->set_from(m_points[prev]);
        m_ray_query->set_to(m_points[i] + seg_vec * (m_collision_radius / seg_len));
        Dictionary entry = space_state->intersect_ray(m_ray_query);
        const Vector3 entry_n = entry.is_empty() ? Vector3() : entry["normal"].operator Vector3();
        // Must be meaningfully behind the entered face (not a corner graze)…
        if (entry_n == Vector3() ||
            (m_points[i] - entry["position"].operator Vector3()).dot(entry_n) > -m_collision_radius)
        {
            m_stuck_passes[i] = 0;
            continue;
        }
        // …and the reverse ray must exit through an opposing face.
        m_ray_query->set_from(m_points[i]);
        m_ray_query->set_to(m_points[prev]);
        Dictionary exit = space_state->intersect_ray(m_ray_query);
        if (exit.is_empty() || entry_n.dot(exit["normal"].operator Vector3()) > -0.7)
        {
            m_stuck_passes[i] = 0;
            continue;
        }
        m_stuck_passes[i] += 1;
        if (m_stuck_passes[i] < 2)
            continue;
        m_stuck_passes[i] = 0;
        m_debug_recoveries += 1;
        m_points[i] = entry["position"].operator Vector3() + entry_n * m_collision_radius;
        m_prev_points[i] = m_points[i];
        m_c_flags[i] = 0;
        m_mid_contact[s] = 0;
        if (m_next_seg[i] >= 0)
            m_mid_contact[m_next_seg[i]] = 0;
    }
}

// Free any particle the last lay buried inside a solid. A cord is laid as a
// straight line between its anchors, and a restore or teleport can put
// furniture on that line. A buried particle is invisible to every contact
// pass — the motion sweep only sees crossings and the rest query refuses
// planes the particle is behind — so it stayed wedged for ever (measured 11 mm
// inside a table). Runs once per lay, on the first tick after it: each buried
// particle is walked out through its nearest face, ray-probed from OUTSIDE
// because a ray cast from inside a solid reports nothing. Point containment
// only answers for convex shapes, which is what furniture is made of; a lay
// through a concave trimesh stays a known gap.
void VerletRope::DepenetrateLay()
{
    if (m_surface_collision_mask == 0 || m_point_query.is_null() ||
        m_ray_query.is_null() || m_shape_query.is_null())
        return;
    Ref<World3D> world = get_world_3d();
    if (world.is_null())
        return;
    PhysicsDirectSpaceState3D *space_state = world->get_direct_space_state();
    if (space_state == nullptr)
        return;

    // A restore can place the whole direct anchor-to-anchor lay through a
    // tabletop. Ejecting each buried particle independently is not sufficient:
    // neighbours choose opposite faces, leaving a segment threaded through the
    // slab and the stretch/contact solvers fight forever. Before the pointwise
    // fallback below, route a buried trunk coherently through a small temporary
    // occupancy grid around its anchors. This is intentionally a one-shot lay
    // repair, not a per-frame pathfinder.
    const auto repair_chain = [&](int first, int point_count, double rest_length) -> bool {
        if (point_count < 2)
            return false;
        bool buried = false;
        for (int k = 1; k < point_count - 1; ++k)
        {
            m_point_query->set_position(m_points[first + k]);
            if (!space_state->intersect_point(m_point_query, 1).is_empty())
            {
                buried = true;
                break;
            }
        }
        // A thin slab can sit wholly between adjacent particle centres, so no
        // point is contained even though the rendered cable passes through it.
        // Opposing hits from the two directions distinguish a true entry/exit
        // crossing from a legitimate graze over a convex edge.
        if (!buried)
        {
            for (int k = 0; k < point_count - 1; ++k)
            {
                const Vector3 a = m_points[first + k];
                const Vector3 b = m_points[first + k + 1];
                m_ray_query->set_from(a);
                m_ray_query->set_to(b);
                const Dictionary entry = space_state->intersect_ray(m_ray_query);
                if (entry.is_empty())
                    continue;
                m_ray_query->set_from(b);
                m_ray_query->set_to(a);
                const Dictionary exit = space_state->intersect_ray(m_ray_query);
                if (exit.is_empty())
                    continue;
                const Vector3 entry_n = entry["normal"];
                const Vector3 exit_n = exit["normal"];
                if (entry_n != Vector3() && exit_n != Vector3() && entry_n.dot(exit_n) < -0.7)
                {
                    buried = true;
                    break;
                }
            }
        }
        if (!buried)
            return false;

        const Vector3 start = m_points[first];
        const Vector3 goal = m_points[first + point_count - 1];
        const double direct = start.distance_to(goal);
        const double slack = std::fmax(0.0, rest_length - direct);
        // The obstacle's nearest edge can be much farther away than the raw
        // cable slack (a controller near the middle of a wide tabletop is the
        // common case), so the search needs a real furniture-sized halo.
        double margin = CLAMP(slack * 0.6 + 0.40, 0.45, 0.90);
        double cell = CLAMP(rest_length / static_cast<double>(point_count - 1) * 2.0,
                            0.055, 0.10);
        Vector3 lo(std::fmin(start.x, goal.x) - margin,
                   std::fmin(start.y, goal.y) - margin,
                   std::fmin(start.z, goal.z) - margin);
        Vector3 hi(std::fmax(start.x, goal.x) + margin,
                   std::fmax(start.y, goal.y) + margin,
                   std::fmax(start.z, goal.z) + margin);

        auto dims_for = [&](double c) {
            return Vector3i(static_cast<int>(std::ceil((hi.x - lo.x) / c)) + 1,
                            static_cast<int>(std::ceil((hi.y - lo.y) / c)) + 1,
                            static_cast<int>(std::ceil((hi.z - lo.z) / c)) + 1);
        };
        Vector3i dims = dims_for(cell);
        constexpr int MAX_NODES = 120000;
        while (static_cast<int64_t>(dims.x) * dims.y * dims.z > MAX_NODES && cell < 0.16)
        {
            cell *= 1.2;
            dims = dims_for(cell);
        }
        const int64_t node_count_64 = static_cast<int64_t>(dims.x) * dims.y * dims.z;
        if (dims.x < 2 || dims.y < 2 || dims.z < 2 || node_count_64 > MAX_NODES)
            return false;
        const int node_count = static_cast<int>(node_count_64);

        const auto clamp_coord = [&](const Vector3 &p) {
            return Vector3i(CLAMP(static_cast<int>(std::lround((p.x - lo.x) / cell)), 0, dims.x - 1),
                            CLAMP(static_cast<int>(std::lround((p.y - lo.y) / cell)), 0, dims.y - 1),
                            CLAMP(static_cast<int>(std::lround((p.z - lo.z) / cell)), 0, dims.z - 1));
        };
        const auto index_of = [&](const Vector3i &c) {
            return (c.z * dims.y + c.y) * dims.x + c.x;
        };
        const auto coord_of = [&](int index) {
            const int x = index % dims.x;
            index /= dims.x;
            const int y = index % dims.y;
            const int z = index / dims.y;
            return Vector3i(x, y, z);
        };
        const Vector3i start_c = clamp_coord(start);
        const Vector3i goal_c = clamp_coord(goal);
        const int start_i = index_of(start_c);
        const int goal_i = index_of(goal_c);
        const auto position_of = [&](int index) {
            if (index == start_i)
                return start;
            if (index == goal_i)
                return goal;
            const Vector3i c = coord_of(index);
            return lo + Vector3(c.x * cell, c.y * cell, c.z * cell);
        };

        std::vector<int8_t> occupied(node_count, -1);
        const auto is_occupied = [&](int index) {
            if (index == start_i || index == goal_i)
                return false;
            if (occupied[index] >= 0)
                return occupied[index] != 0;
            m_shape_query->set_motion(Vector3());
            m_shape_query->set_transform(Transform3D(Basis(), position_of(index)));
            const bool hit = !space_state->intersect_shape(m_shape_query, 1).is_empty();
            occupied[index] = hit ? 1 : 0;
            return hit;
        };

        const double inf = std::numeric_limits<double>::infinity();
        std::vector<double> cost(node_count, inf);
        std::vector<int> parent(node_count, -1);
        using OpenNode = std::pair<double, int>;
        std::priority_queue<OpenNode, std::vector<OpenNode>, std::greater<OpenNode>> open;
        cost[start_i] = 0.0;
        open.push({start.distance_to(goal), start_i});
        int expanded = 0;
        while (!open.empty() && expanded++ < MAX_NODES)
        {
            const int current = open.top().second;
            open.pop();
            if (current == goal_i)
                break;
            const Vector3i cc = coord_of(current);
            for (int dz = -1; dz <= 1; ++dz)
            for (int dy = -1; dy <= 1; ++dy)
            for (int dx = -1; dx <= 1; ++dx)
            {
                if (dx == 0 && dy == 0 && dz == 0)
                    continue;
                const Vector3i step(dx, dy, dz);
                const Vector3i nc = cc + step;
                if (nc.x < 0 || nc.y < 0 || nc.z < 0 ||
                    nc.x >= dims.x || nc.y >= dims.y || nc.z >= dims.z)
                    continue;
                const int next = index_of(nc);
                if (is_occupied(next))
                    continue;
                const Vector3 current_pos = position_of(current);
                const Vector3 next_pos = position_of(next);
                // An attachment point may legitimately begin just inside the
                // supporting tabletop even though its host body is excluded.
                // A shape cast starting overlapped reports zero safe motion in
                // every direction and strands the A* start. Let the first/last
                // edge escape; the neighbouring cell itself must still be free.
                if (current != start_i && next != goal_i)
                {
                    m_shape_query->set_transform(Transform3D(Basis(), current_pos));
                    m_shape_query->set_motion(next_pos - current_pos);
                    const PackedFloat32Array sweep = space_state->cast_motion(m_shape_query);
                    if (sweep.size() >= 1 && sweep[0] < 0.999f)
                        continue;
                }
                const double next_cost = cost[current] + current_pos.distance_to(next_pos);
                if (next_cost >= cost[next])
                    continue;
                cost[next] = next_cost;
                parent[next] = current;
                open.push({next_cost + position_of(next).distance_to(goal), next});
            }
        }
        m_shape_query->set_motion(Vector3());
        if (start_i != goal_i && parent[goal_i] < 0)
            return false;

        std::vector<Vector3> path;
        for (int at = goal_i; at >= 0; at = parent[at])
        {
            path.push_back(position_of(at));
            if (at == start_i)
                break;
        }
        if (path.size() < 2 || path.back().distance_squared_to(start) > 1e-8)
            return false;
        std::reverse(path.begin(), path.end());

        std::vector<double> cumulative(path.size(), 0.0);
        for (size_t i = 1; i < path.size(); ++i)
            cumulative[i] = cumulative[i - 1] + path[i - 1].distance_to(path[i]);
        const double path_length = cumulative.back();
        // A restored placement can be slightly beyond the cable's true reach.
        // Keep a coherent route up to a bounded 1.5x strain; the ordinary
        // tension/coupling path can then move a free endpoint. Rejecting it here
        // falls back to the much worse state of a short segment threaded through
        // the obstacle.
        if (path_length < 1e-6 || path_length > rest_length * 1.5)
            return false;
        for (int k = 0; k < point_count; ++k)
        {
            const double target = path_length * static_cast<double>(k) /
                                  static_cast<double>(point_count - 1);
            size_t edge = 1;
            while (edge < cumulative.size() && cumulative[edge] < target)
                ++edge;
            if (edge >= cumulative.size())
                edge = cumulative.size() - 1;
            const double span = cumulative[edge] - cumulative[edge - 1];
            const double t = span > 1e-9 ? (target - cumulative[edge - 1]) / span : 0.0;
            m_points[first + k] = path[edge - 1].lerp(path[edge], t);
            m_prev_points[first + k] = m_points[first + k];
        }
        return true;
    };

    const bool trunk_repaired = repair_chain(0, TrunkCount(), RestLength());
    if (trunk_repaired)
    {
        std::fill(m_c_flags.begin(), m_c_flags.end(), 0);
        std::fill(m_mid_contact.begin(), m_mid_contact.end(), 0);
        std::fill(m_stuck_passes.begin(), m_stuck_passes.end(), 0);
    }
    // Deeper than half a PROBE inside anything and the lay was hopeless anyway.
    constexpr double PROBE = 0.6;
    static const Vector3 DIRS[6] = {Vector3(1, 0, 0),  Vector3(-1, 0, 0), Vector3(0, 1, 0),
                                    Vector3(0, -1, 0), Vector3(0, 0, 1),  Vector3(0, 0, -1)};
    const int count = static_cast<int>(m_points.size());
    for (int i = 0; i < count; ++i)
    {
        if (m_inv_mass[i] == 0.0f)
            continue;
        m_point_query->set_position(m_points[i]);
        if (space_state->intersect_point(m_point_query, 1).is_empty())
            continue;
        double best = PROBE;
        Vector3 best_pos;
        Vector3 best_n;
        for (const Vector3 &d : DIRS)
        {
            m_ray_query->set_from(m_points[i] + d * PROBE);
            m_ray_query->set_to(m_points[i]);
            Dictionary hit = space_state->intersect_ray(m_ray_query);
            if (hit.is_empty())
                continue;
            const Vector3 hp = hit["position"];
            const double dist = hp.distance_to(m_points[i]);
            if (dist < best)
            {
                best = dist;
                best_pos = hp;
                best_n = hit["normal"];
            }
        }
        if (best >= PROBE || best_n == Vector3())
            continue;
        m_points[i] = best_pos + best_n * m_collision_radius;
        m_prev_points[i] = m_points[i];
    }
}

// Pull back on an anchor's rigidbody when the cable it holds is stretched past
// its rest length. This is the ONLY path by which the rope moves a plug: a
// pinned particle has inverse mass 0, so the plug drives the rope and never the
// other way about.
void VerletRope::ApplyAnchorCoupling()
{
    if (m_anchor_pull <= 0.0)
        return;

    // Trunk, between its own two anchors. Needs both: with a fray there is no
    // trunk anchor at all and the branches below do the work instead.
    if (m_start_cached && m_end_cached)
    {
        const Vector3 ps = AnchorPoint(m_start_cached, m_start_anchor_offset, Vector3());
        const Vector3 pe = AnchorPoint(m_end_cached, m_end_anchor_offset, Vector3());
        const double excess = ps.distance_to(pe) - RestLength();
        if (excess > 0.0)
        {
            const double force = excess * m_anchor_pull;
            if (m_start_body)
                m_start_body->apply_force((pe - ps).normalized() * force,
                                          ps - m_start_body->get_global_position());
            if (m_end_body)
                m_end_body->apply_force((ps - pe).normalized() * force,
                                        pe - m_end_body->get_global_position());
        }
    }

    // Each branch, between its plug and the breakout it hangs off. Without this
    // a lead frayed at both ends has no coupling whatsoever — pick up one plug of
    // a composite lead, walk away, and the other five sit exactly where they are
    // while the cable stretches without limit.
    for (const FrayChain &fc : m_fray)
    {
        if (fc.body == nullptr)
            continue;
        const Vector3 plug = AnchorPoint(fc.cached, fc.offset, Vector3());
        const Vector3 junction = m_points[fc.head];
        const double excess = plug.distance_to(junction) - fc.count * FraySegLength();
        if (excess <= 0.0)
            continue;
        fc.body->apply_force((junction - plug).normalized() * (excess * m_anchor_pull),
                             plug - fc.body->get_global_position());
    }
}

void VerletRope::UpdateSleepState()
{
    const int count = static_cast<int>(m_points.size());
    double max_velocity_sq = 0.0;
    double velocity_sum_sq = 0.0;
    // Measure final-pose motion from the previous physics tick, not Verlet's
    // internal current-minus-history velocity. Constraints intentionally edit
    // the latter: a directional strain-relief boot corrects its first particle
    // after stretch on every iteration and can therefore report perpetual
    // energy even after the visible centreline has reached a fixed point. The
    // render snapshot is rolled only after this function, so m_curr_render is
    // exactly the preceding tick's solved particle layout.
    const bool have_previous_pose = static_cast<int>(m_curr_render.size()) == count;
    for (int i = 0; i < count; ++i)
    {
        const double velocity_sq = have_previous_pose
                                       ? m_points[i].distance_squared_to(m_curr_render[i])
                                       : m_points[i].distance_squared_to(m_prev_points[i]);
        max_velocity_sq = std::max(max_velocity_sq, velocity_sq);
        velocity_sum_sq += velocity_sq;
    }
    // Gate both the peak and the rope's actual pose energy so localized solver
    // dust can sleep but visible whole-cable squirm cannot.
    const bool velocity_still = max_velocity_sq <= SLEEP_MAX_VELOCITY_EPS_SQ &&
                                velocity_sum_sq / std::max(1, count) <=
                                    SLEEP_RMS_VELOCITY_EPS_SQ;
    m_debug_max_velocity = std::sqrt(max_velocity_sq);
    m_debug_rms_velocity = std::sqrt(velocity_sum_sq / std::max(1, count));

    double worst_stretch_error = 0.0;
    int worst_stretch_segment = -1;
    for (int s = 0; s < static_cast<int>(m_seg_a.size()); ++s)
    {
        const double rest = m_seg_rest[s];
        if (rest > 1e-8)
        {
            const double error =
                std::abs(m_points[m_seg_a[s]].distance_to(m_points[m_seg_b[s]]) - rest) / rest;
            if (error > worst_stretch_error)
            {
                worst_stretch_error = error;
                worst_stretch_segment = s;
            }
        }
    }

    double worst_contact_error = 0.0;
    for (int i = 0; i < count; ++i)
    {
        if (m_c_flags[i] & 1)
        {
            worst_contact_error = std::max(
                worst_contact_error,
                std::max(0.0, m_collision_radius - (m_points[i] - m_c_p1[i]).dot(m_c_n1[i])));
        }
        if (m_c_flags[i] & 2)
        {
            worst_contact_error = std::max(
                worst_contact_error,
                std::max(0.0, m_collision_radius - (m_points[i] - m_c_p2[i]).dot(m_c_n2[i])));
        }
    }
    for (int s = 0; s < static_cast<int>(m_mid_contact.size()); ++s)
    {
        if (m_mid_contact[s] == 0)
            continue;
        if (m_mid_contact[s] & 1)
        {
            const Vector3 p = m_points[m_seg_a[s]].lerp(m_points[m_seg_b[s]],
                                                        m_mid_contact_t[s]);
            worst_contact_error = std::max(
                worst_contact_error,
                std::max(0.0, m_collision_radius -
                                  (p - m_mid_contact_point[s]).dot(m_mid_contact_normal[s])));
        }
        if (m_mid_contact[s] & 2)
        {
            const Vector3 p = m_points[m_seg_a[s]].lerp(m_points[m_seg_b[s]],
                                                        m_mid_contact_t_2[s]);
            worst_contact_error = std::max(
                worst_contact_error,
                std::max(0.0, m_collision_radius -
                                  (p - m_mid_contact_point_2[s]).dot(m_mid_contact_normal_2[s])));
        }
    }
    if (worst_contact_error <= SLEEP_CONTACT_ERROR)
        m_contact_stable_frames += 1;
    else
        m_contact_stable_frames = 0;

    const Vector3 a_start = AnchorPoint(m_start_cached, m_start_anchor_offset, m_sleep_anchor_start);
    const Vector3 a_end = AnchorPoint(m_end_cached, m_end_anchor_offset, m_sleep_anchor_end);
    bool anchors_still = true;
    // Hosts, sockets and hands are external authority and must be stationary.
    // A free plug belongs to the rope system itself; Jolt can roll its small
    // sphere by microscopic amounts forever, and SleepNow is specifically what
    // latches that body once the cable's kinetic criteria are met.
    const EndpointRole sleep_start_role = ResolveEndpointRole(m_start_cached, m_start_endpoint_role);
    const EndpointRole sleep_end_role = ResolveEndpointRole(m_end_cached, m_end_endpoint_role);
    const auto quiet_host = [](RigidBody3D *body, EndpointRole role) {
        return role == ENDPOINT_HOST && body != nullptr &&
               body->get_linear_velocity().length_squared() < 0.3 * 0.3 &&
               body->get_angular_velocity().length_squared() < 3.0 * 3.0;
    };
    if (!EndpointIsFree(sleep_start_role) && !quiet_host(m_start_body, sleep_start_role) &&
        a_start.distance_squared_to(m_sleep_anchor_start) > WAKE_ANCHOR_EPS_SQ)
        anchors_still = false;
    if (!EndpointIsFree(sleep_end_role) && !quiet_host(m_end_body, sleep_end_role) &&
        a_end.distance_squared_to(m_sleep_anchor_end) > WAKE_ANCHOR_EPS_SQ)
        anchors_still = false;
    m_sleep_anchor_start = a_start;
    m_sleep_anchor_end = a_end;
    for (FrayChain &fc : m_fray)
    {
        const Vector3 a = AnchorPoint(fc.cached, fc.offset, fc.sleep_pos);
        if (!EndpointIsFree(ResolveEndpointRole(fc.cached, ENDPOINT_AUTO)) &&
            a.distance_squared_to(fc.sleep_pos) > WAKE_ANCHOR_EPS_SQ)
            anchors_still = false;
        fc.sleep_pos = a;
    }
    if (!anchors_still)
        m_contact_stable_frames = 0;
    const bool constraints_settled = worst_stretch_error <= SLEEP_STRETCH_ERROR &&
                                     worst_contact_error <= SLEEP_CONTACT_ERROR;
    m_debug_stretch_error = worst_stretch_error;
    m_debug_contact_error = worst_contact_error;
    // A lay that cannot be: a segment several times its length for two seconds
    // with both ends still. The usual way in is a plug seated in a port on the
    // FAR side of its console from where the cord lies: the cord's last segment
    // then runs through the console, the last free particle is pressed against
    // the near face with nowhere to go, and the cord can never settle, sleep or
    // stop twitching (a Genesis pad's cord in the room, 2026-11-10: one segment
    // 7.5x its length through 21 cm of console). The wrong-side recovery walks a
    // particle back to its predecessor, which is no help when the far end is
    // the pinned one. Lay the cord afresh between its ends, once, as a teleport
    // does (DepenetrateLay then routes it round what is in the way), and not
    // again until an end has moved.
    if (!anchors_still)
    {
        m_hopeless_frames = 0;
        m_relay_attempted = false;
    }
    else if (worst_stretch_error > SLEEP_STRETCH_ERROR)
        m_hopeless_frames += 1;
    else
        m_hopeless_frames = 0;
    if (m_hopeless_frames > HOPELESS_FRAMES && !m_relay_attempted)
    {
        m_relay_attempted = true;
        m_hopeless_frames = 0;
        UtilityFunctions::print("[Rope] ", get_path(), ": segment ", worst_stretch_segment, " is ",
                                worst_stretch_error + 1.0, "x its length and has been for ",
                                HOPELESS_FRAMES, " ticks with both ends still; laying the cord afresh");
        InitPoints();
        return;
    }
    // A controller or sensor bar is the physical host at a plain Node3D anchor.
    // Jolt may keep a resting host microscopically rocking on an edge; because
    // the endpoint is pinned, that motion drives the whole cable forever. Once
    // the rope manifold is established and the host itself is already moving
    // below ordinary grab/throw speeds, let the physics body sleep. Any grab,
    // force or transform change wakes the body and AnchorsMoved wakes the rope.
    const auto latch_resting_host = [this](RigidBody3D *body, EndpointRole role) {
        if (body == nullptr || role != ENDPOINT_HOST || body->is_sleeping())
            return;
        if (body->has_method("is_picked_up") && static_cast<bool>(body->call("is_picked_up")))
            return;
        if (body->get_linear_velocity().length_squared() < 0.3 * 0.3 &&
            body->get_angular_velocity().length_squared() < 3.0 * 3.0)
            body->set_sleeping(true);
    };
    if (m_contact_stable_frames > 90 && constraints_settled)
    {
        latch_resting_host(m_start_body, sleep_start_role);
        latch_resting_host(m_end_body, sleep_end_role);
    }
    // A restored legacy lay can be legal at every particle yet have one segment
    // trapped between stale planes on opposite sides of furniture. Contact then
    // wins the last write of every iteration and leaves that segment >2x long,
    // injecting a large correction forever. Drop only the local manifold once;
    // the swept/rest queries rebuild it from the live geometry next tick.
    if (!m_settle_repair_attempted && m_contact_stable_frames > 180 &&
        m_debug_max_velocity > 0.005 && worst_stretch_error > 0.5 &&
        worst_stretch_segment >= 0)
    {
        const int a = m_seg_a[worst_stretch_segment];
        const int b = m_seg_b[worst_stretch_segment];
        m_c_flags[a] = 0;
        m_c_flags[b] = 0;
        m_mid_contact[worst_stretch_segment] = 0;
        if (m_next_seg[a] >= 0)
            m_mid_contact[m_next_seg[a]] = 0;
        if (m_next_seg[b] >= 0)
            m_mid_contact[m_next_seg[b]] = 0;
        m_prev_points = m_points;
        m_contact_stable_frames = 0;
        m_settle_repair_attempted = true;
    }
    // A contact-driven limit cycle can continuously replace the tiny amount of
    // global Verlet damping (edge impact -> stretch correction -> edge impact).
    // Once the manifold and anchors have stayed valid for a full second, add
    // physical contact damping to the history. The ordinary velocity gate still
    // decides sleep; this merely lets energy leave instead of freezing motion.
    if (!velocity_still && anchors_still && constraints_settled &&
        m_contact_stable_frames > 90)
    {
        constexpr double CONTACT_SETTLE_RETAIN = 0.5;
        for (int i = 0; i < count; ++i)
            if (m_inv_mass[i] != 0.0f)
                m_prev_points[i] = m_points[i] -
                                   (m_points[i] - m_prev_points[i]) * CONTACT_SETTLE_RETAIN;
    }
    // XENU_ROPE_DIAG=1: once a second, every cord that is awake says what is
    // keeping it awake. A cord that will not lie still in a room cannot be read
    // from a probe that does not have the room.
    static const bool diag = std::getenv("XENU_ROPE_DIAG") != nullptr;
    if (diag)
    {
        m_diag_ticks += 1;
        m_diag_not_still += velocity_still ? 0 : 1;
        m_diag_anchor_moved += anchors_still ? 0 : 1;
        m_diag_unsettled += constraints_settled ? 0 : 1;
        m_diag_peak = std::max(m_diag_peak, m_debug_max_velocity);
        if (m_diag_ticks == 89 && m_self_contacts.size() > 20)
        {
            for (const SelfContact &c : m_self_contacts)
                if (c.pushed > 0.0002)
                    UtilityFunctions::print("[Rope]     (tick before) self a ", c.a0, "-", c.a1, " s ", c.s, " b ", c.b0, "-",
                                            c.b1, " t ", c.t, " pushed ", c.pushed * 1000.0, " w ", c.wa0, " ", c.wa1, " ",
                                            c.wb0, " ", c.wb1, " flags ", m_c_flags[c.a0], m_c_flags[c.a1],
                                            m_c_flags[c.b0], m_c_flags[c.b1], " ya ", m_points[c.a0].y, " yb ", m_points[c.b0].y);
        }
        if (m_diag_ticks >= 90)
        {
            UtilityFunctions::print(
                "[Rope] ", get_path(), " awake 90 ticks: moving ", m_diag_not_still,
                ", anchor moved ", m_diag_anchor_moved, ", unsettled ", m_diag_unsettled,
                ", wakes anchor/env/call ", m_diag_wake_anchor, "/", m_diag_wake_env, "/", m_diag_wake_call,
                ", peak ", m_diag_peak * 1000.0, " mm/tick, now max ", m_debug_max_velocity * 1000.0,
                " rms ", m_debug_rms_velocity * 1000.0, " stretch ", worst_stretch_error,
                " contact ", worst_contact_error, ", stable ", m_contact_stable_frames,
                ", self contacts ", static_cast<int>(m_self_contacts.size()),
                ", ends ", static_cast<int>(sleep_start_role), "/", static_cast<int>(sleep_end_role));
            if (worst_stretch_segment >= 0 && worst_stretch_error > 0.5)
            {
                const int sa = m_seg_a[worst_stretch_segment];
                const int sb = m_seg_b[worst_stretch_segment];
                UtilityFunctions::print(
                    "[Rope]   longest segment ", worst_stretch_segment, " of ",
                    static_cast<int>(m_seg_a.size()), ": p", sa, " ", m_points[sa], " w ", m_inv_mass[sa],
                    " flags ", m_c_flags[sa], " n1 ", m_c_n1[sa], " -> p", sb, " ", m_points[sb], " w ",
                    m_inv_mass[sb], " flags ", m_c_flags[sb], " n1 ", m_c_n1[sb], "; its contact ",
                    m_mid_contact[worst_stretch_segment], " at ", m_mid_contact_point[worst_stretch_segment],
                    " n ", m_mid_contact_normal[worst_stretch_segment], " t ",
                    m_mid_contact_t[worst_stretch_segment], "; anchors ", a_start, " ", a_end);
                }
                {
                // What the cord's contacts with itself are doing: the mover, and
                // every contact that pushed this tick.
                int mover = 0;
                double most = 0.0;
                for (int i = 0; i < count && have_previous_pose; ++i)
                {
                    const double d = m_points[i].distance_squared_to(m_curr_render[i]);
                    if (d > most)
                    {
                        most = d;
                        mover = i;
                    }
                }
                UtilityFunctions::print("[Rope]   mover p", mover, " of ", count, " (trunk ", TrunkCount(),
                                        ") moved ", m_points[mover] - m_curr_render[mover], " at ",
                                        m_points[mover], " flags ", m_c_flags[mover], " w ", m_inv_mass[mover]);
                int shown = 0;
                for (const SelfContact &c : m_self_contacts)
                    if (c.pushed > 0.0002 && shown++ < 12)
                        UtilityFunctions::print("[Rope]     self a ", c.a0, "-", c.a1, " s ", c.s, " b ", c.b0, "-",
                                                c.b1, " t ", c.t, " pushed ", c.pushed * 1000.0, " w ", c.wa0, " ", c.wa1, " ",
                                                c.wb0, " ", c.wb1, " flags ", m_c_flags[c.a0], m_c_flags[c.a1],
                                                m_c_flags[c.b0], m_c_flags[c.b1], " ya ", m_points[c.a0].y, " yb ", m_points[c.b0].y,
                                                " fixed ", c.fixed, " n ", c.normal);
                }
                if (worst_stretch_segment >= 0 && worst_stretch_error > 0.5)
                {
                const int sa = m_seg_a[worst_stretch_segment];
                const int sb = m_seg_b[worst_stretch_segment];
                // What stands between the two ends of that segment.
                Ref<World3D> diag_world = get_world_3d();
                if (diag_world.is_valid() && m_ray_query.is_valid())
                {
                    PhysicsDirectSpaceState3D *diag_space = diag_world->get_direct_space_state();
                    for (int way = 0; way < 2 && diag_space != nullptr; ++way)
                    {
                        m_ray_query->set_from(m_points[way == 0 ? sa : sb]);
                        m_ray_query->set_to(m_points[way == 0 ? sb : sa]);
                        const Dictionary between = diag_space->intersect_ray(m_ray_query);
                        Node *who = between.is_empty() ? nullptr
                                                       : Object::cast_to<Node>(between["collider"].operator Object *());
                        UtilityFunctions::print("[Rope]   ray p", way == 0 ? sa : sb, " -> p", way == 0 ? sb : sa,
                                                ": ", who != nullptr ? String(who->get_path()) : String("nothing"),
                                                between.is_empty() ? Variant() : between["position"],
                                                between.is_empty() ? Variant() : between["normal"]);
                    }
                    UtilityFunctions::print("[Rope]   start node ", m_start_cached ? String(m_start_cached->get_path()) : String("-"),
                                            ", end node ", m_end_cached ? String(m_end_cached->get_path()) : String("-"));
                }
            }
            m_diag_ticks = m_diag_not_still = m_diag_anchor_moved = m_diag_unsettled = 0;
            m_diag_wake_anchor = m_diag_wake_env = m_diag_wake_call = 0;
            m_diag_peak = 0.0;
        }
    }
    if (velocity_still && anchors_still && constraints_settled &&
        m_contact_stable_frames >= m_raycast_interval * 2)
    {
        m_still_frames += 1;
        if (m_still_frames >= SLEEP_FRAMES)
        {
            SleepNow();
        }
    }
    else
        m_still_frames = std::max(0, m_still_frames - 1);
}

} // namespace Xenu
