#include "GrabDriverTick.hpp"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/object.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/quaternion.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/vector3.hpp>

using namespace godot;

namespace Xenu
{

int64_t GrabDriverTick::s_holder_epoch = 0;

namespace
{
// Interned once, after godot-cpp is up (a namespace-scope StringName would be
// built before the library is initialised).
struct Names
{
    StringName target{"target"};
    StringName primary{"primary"};
    StringName secondary{"secondary"};
    StringName state{"state"};
    StringName by{"by"};
    StringName transform{"transform"};
    StringName drive_position{"drive_position"};
    StringName drive_angle{"drive_angle"};
    StringName drive_aim{"drive_aim"};
    StringName lerp_time{"lerp_time"};
    StringName lerp_duration{"lerp_duration"};
    StringName lerp_start{"lerp_start"};
    StringName set_arrived{"set_arrived"};
    StringName constrain_grab{"constrain_grab"};
    StringName constrains_field{"_constrains"};
    StringName constrain_target_field{"_constrain_target"};
    // grab_driver.gd's helpers for this node.
    StringName target_gone{"_target_gone"};
    StringName note_resting{"_note_resting"};
    StringName update_weight{"_update_weight"};
    StringName by_zone{"_by_zone"};
    StringName priority_for{"_priority_for"};
    StringName preview_step{"_preview_step"};
};

const Names &names()
{
    static const Names n;
    return n;
}

// grab_driver.gd's _vote, in GDScript's float (double).
double vote(double a, double b)
{
    if (a == 0.0 && b == 0.0)
        return 0.0;
    return b / (a + b);
}

// GDScript's `is_instance_valid(v)`, and then the object: nullptr for null or freed. Read by the
// Variant's object id (never through its pointer, which a freed object leaves dangling).
Object *valid_object(const Variant &v)
{
    if (v.get_type() != Variant::OBJECT)
        return nullptr;
    const ObjectID id = v;
    if (!id.is_valid())
        return nullptr;
    return ObjectDB::get_instance(uint64_t(id));
}
} // namespace

void GrabDriverTick::_bind_methods()
{
    ClassDB::bind_method(D_METHOD("reset_rest"), &GrabDriverTick::reset_rest);
    ClassDB::bind_method(D_METHOD("get_pushed_once"), &GrabDriverTick::get_pushed_once);
    ClassDB::bind_method(D_METHOD("get_rest_ticks"), &GrabDriverTick::get_rest_ticks);
    ClassDB::bind_static_method("GrabDriverTick", D_METHOD("set_holder_epoch", "epoch"),
                                &GrabDriverTick::set_holder_epoch);
    ClassDB::bind_static_method("GrabDriverTick", D_METHOD("get_holder_epoch"),
                                &GrabDriverTick::get_holder_epoch);
}

void GrabDriverTick::set_holder_epoch(int64_t p_epoch)
{
    s_holder_epoch = p_epoch;
}

int64_t GrabDriverTick::get_holder_epoch()
{
    return s_holder_epoch;
}

void GrabDriverTick::reset_rest()
{
    m_rest_ticks = 0;
}

// Line for line grab_driver.gd's _physics_process (its LOCAL PATCH comments say
// why each part is there); grab_driver_tests holds the two to the same poses.
void GrabDriverTick::_physics_process(double p_delta)
{
    const Names &n = names();

    Node3D *driver = Object::cast_to<Node3D>(get_parent());
    if (driver == nullptr)
    {
        if (!m_logged_lost_driver)
        {
            m_logged_lost_driver = true;
            UtilityFunctions::print("[Grab] GrabDriverTick ", get_name(), " has no driver above it; idle");
        }
        set_physics_process(false);
        return;
    }

    // A driver whose target was freed while held goes away (the script says so and frees itself).
    Object *target_obj = valid_object(driver->get(n.target));
    if (target_obj == nullptr)
    {
        set_physics_process(false);
        driver->call(n.target_gone);
        return;
    }
    Node3D *target = Object::cast_to<Node3D>(target_obj);

    // Skip if no primary node or its grabber has been freed.
    Variant primary_v = driver->get(n.primary);
    Object *primary = valid_object(primary_v);
    if (primary == nullptr)
        return;
    Node3D *by = Object::cast_to<Node3D>(valid_object(primary->get(n.by)));
    if (by == nullptr)
        return;

    Variant secondary_v = driver->get(n.secondary);
    Object *secondary = valid_object(secondary_v);
    int64_t state = driver->get(n.state);

    // Resting in a snap zone that has not moved, with the holder graph unchanged: nothing to compute.
    if (m_pushed_once && state == STATE_SNAP && primary == m_primary_cached_ptr &&
        m_primary_by_zone && secondary == nullptr && !m_constrains)
    {
        Transform3D zone_xf = by->get_global_transform();
        if (zone_xf.is_equal_approx(m_rest_zone_xf) && s_holder_epoch == m_priority_epoch)
        {
            m_rest_ticks += 1;
            if (m_rest_ticks >= REST_AFTER)
            {
                set_physics_process(false);
                driver->call(n.note_resting);
            }
            return;
        }
        m_rest_zone_xf = zone_xf;
    }
    m_rest_ticks = 0;

    // Set destination from primary grab.
    const Transform3D by_xf = by->get_global_transform();
    const Transform3D primary_xf = primary->get(n.transform);
    Transform3D destination = by_xf * primary_xf.affine_inverse();

    // If present, apply secondary-node contributions.
    if (secondary != nullptr)
    {
        Node3D *sby = Object::cast_to<Node3D>(valid_object(secondary->get(n.by)));
        if (sby == nullptr)
            return; // the script would stop here on a freed secondary grabber too
        const Transform3D secondary_xf = secondary->get(n.transform);

        double position_lerp = vote(primary->get(n.drive_position), secondary->get(n.drive_position));
        double angle_lerp = vote(primary->get(n.drive_angle), secondary->get(n.drive_angle));

        Transform3D x1 = destination;
        Transform3D x2 = sby->get_global_transform() * secondary_xf.affine_inverse();

        // Independently lerp the angle and position.
        destination = Transform3D(
            x1.basis.slerp(x2.basis, real_t(angle_lerp)),
            x1.origin.lerp(x2.origin, real_t(position_lerp)));

        double drive_aim = secondary->get(n.drive_aim);
        if (drive_aim > 0.0)
        {
            // Convert destination from global to primary-local.
            destination = by_xf.affine_inverse() * destination;

            // The from and to vectors in primary-local space.
            Vector3 secondary_from = destination.xform(secondary_xf.origin);
            Vector3 secondary_to = by->to_local(sby->get_global_position());

            // Shortest arc.
            secondary_from = secondary_from.normalized();
            secondary_to = secondary_to.normalized();
            Quaternion spherical(secondary_from, secondary_to);

            // Aim rotation.
            Basis rotate = Basis().slerp(Basis(spherical), real_t(drive_aim));
            destination = Transform3D(rotate, Vector3()) * destination;

            // Back from primary-local to global.
            destination = by_xf * destination;
        }
    }

    // Handle update.
    if (state == STATE_LERP)
    {
        double lerp_time = double(driver->get(n.lerp_time)) + p_delta;
        driver->set(n.lerp_time, lerp_time);
        double lerp_duration = driver->get(n.lerp_duration);
        if (lerp_time < lerp_duration)
        {
            const Transform3D lerp_start = driver->get(n.lerp_start);
            destination = lerp_start.interpolate_with(destination, real_t(lerp_time / lerp_duration));
        }
        else
        {
            // Lerp completed. Each call may let go of the object, so every field is read again after it.
            state = STATE_SNAP;
            driver->set(n.state, STATE_SNAP);
            driver->call(n.update_weight);
            if (Object *p = valid_object(driver->get(n.primary)))
                p->call(n.set_arrived);
            if (Object *s = valid_object(driver->get(n.secondary)))
                s->call(n.set_arrived);
        }
    }

    // `primary.by is XRToolsSnapZone`, worked out once per Grab.
    primary_v = driver->get(n.primary);
    primary = valid_object(primary_v);
    if (primary == nullptr)
        return; // let go mid-tick: the script would have stopped on `primary.by` too
    if (primary != m_primary_cached_ptr)
    {
        m_primary_cached = primary_v;
        m_primary_cached_ptr = primary;
        m_primary_by_zone = driver->call(n.by_zone, primary_v);
    }

    // Snap-zone preview of an object held by anything but a socket: the room's to decide, so the script's.
    if (state == STATE_SNAP && valid_object(driver->get(n.target)) != nullptr && !m_primary_by_zone)
        destination = driver->call(n.preview_step, destination, p_delta);

    // The holder graph changed: this driver may now sit at another depth of a stack of sockets.
    if (m_primary_by_zone && s_holder_epoch != m_priority_epoch)
    {
        m_priority_epoch = s_holder_epoch;
        int64_t want = driver->call(n.priority_for, primary_v);
        if (want != driver->get_physics_process_priority())
            driver->set_physics_process_priority(int32_t(want));
        if (want != get_physics_process_priority())
            set_physics_process_priority(int32_t(want));
    }

    // A held object that is turned by the hand rather than carried says where the hold really puts it.
    target_obj = valid_object(driver->get(n.target));
    target = Object::cast_to<Node3D>(target_obj);
    ObjectID target_id = target_obj != nullptr ? ObjectID(target_obj->get_instance_id()) : ObjectID();
    if (target_id != m_constrain_target)
    {
        m_constrain_target = target_id;
        m_constrains = target_obj != nullptr && target_obj->has_method(n.constrain_grab);
        // The script's own copies, which code outside the tick reads (arcade_form_tests asks `_constrains`).
        driver->set(n.constrains_field, m_constrains);
        driver->set(n.constrain_target_field, target_obj != nullptr ? Variant(target_obj) : Variant());
    }
    if (m_constrains)
        destination = target_obj->call(n.constrain_grab, destination);

    // Always push once, however the driver was built.
    if (m_pushed_once && driver->get_global_transform().is_equal_approx(destination))
        return;
    m_pushed_once = true;

    // Apply the destination transform.
    driver->set_global_transform(destination);
    driver->force_update_transform();
    if (target != nullptr)
        target->force_update_transform();
}

} // namespace Xenu
