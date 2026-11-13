#pragma once

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/core/object_id.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/variant.hpp>

namespace Xenu
{

// The per-physics-tick half of godot-xr-tools' XRToolsGrabDriver
// (RetroXR/addons/godot-xr-tools/objects/grab_points/grab_driver.gd).
//
// The GDScript class stays the driver: its fields (primary, secondary, state,
// target, lerp_*), its API (add_grab, remove_grab, discard, create_snap,
// create_lerp, wake, wake_all) and its snap-preview helpers are untouched, and
// its own _physics_process is the fallback and the reference. A driver that
// finds this class adds one as an INTERNAL child at its own physics priority
// and stops ticking itself; this node then does, every tick, exactly what
// _physics_process does -- the resting early-out, the destination from the
// primary and secondary grabs, the lerp, the holder-epoch priority, the swivel
// constraint and the push -- reading the driver's fields and calling back into
// its script only for what is rare or is the room's (a lerp arriving, the
// snap-preview step of a hand-held object, a new priority, a freed target).
//
// Why: each driver whose object sits in a socket ticks for as long as it is
// held, and 213 of them in GDScript were 0.9 ms of a Quest 3's debug frame,
// nearly all of it the cost of entering a script function (2026-11-13).
class GrabDriverTick : public godot::Node
{
    GDCLASS(GrabDriverTick, godot::Node)

public:
    // grab_driver.gd's REST_AFTER and GrabState.
    static constexpr int REST_AFTER = 30;
    static constexpr int STATE_LERP = 0;
    static constexpr int STATE_SNAP = 1;

    void _physics_process(double p_delta) override;

    // XRToolsGrabDriver.wake(): the rest count starts again.
    void reset_rest();

    // XRToolsSnapZone's holder epoch, pushed by XRToolsGrabDriver.wake_all(),
    // which XRToolsSnapZone._note_held calls after every bump.
    static void set_holder_epoch(int64_t p_epoch);
    static int64_t get_holder_epoch();

    // For the test suite: what this tick has cached.
    bool get_pushed_once() const { return m_pushed_once; }
    int get_rest_ticks() const { return m_rest_ticks; }

protected:
    static void _bind_methods();

private:
    static int64_t s_holder_epoch;

    bool m_pushed_once = false;
    godot::Transform3D m_rest_zone_xf;
    int m_rest_ticks = 0;
    int64_t m_priority_epoch = -1;
    // The Grab `primary` was when m_primary_by_zone was worked out (a strong
    // reference, as the script's _primary_cached is).
    godot::Variant m_primary_cached;
    godot::Object *m_primary_cached_ptr = nullptr;
    bool m_primary_by_zone = false;
    godot::ObjectID m_constrain_target;
    bool m_constrains = false;
    bool m_logged_lost_driver = false;
};

} // namespace Xenu
