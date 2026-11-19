// The cord's own collision (docs/dev/rope-collision-plan.md, stage 1).
//
// GatherShapes (main thread) asks the engine once for the bodies near the cord
// and reads their shapes into m_near. ContactsFromShapes (any thread) tests
// the cord's particles and segments against that list and writes the contact
// planes the solver already knows how to stand on. Nothing is remembered from
// one slice to the next: a plane is where the surface IS, every time.

#include "VerletRope.hpp"

#include <godot_cpp/classes/physics_direct_space_state3d.hpp>
#include <godot_cpp/classes/physics_server3d.hpp>
#include <godot_cpp/classes/physics_shape_query_parameters3d.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <cmath>
#include <unordered_map>

using namespace godot;

namespace Xenu
{

namespace
{
// More bodies than this near one cord and the rest are left out (said once).
constexpr int GATHER_MAX = 48;
// The box asked about reaches this far past the cord, on top of its jacket.
constexpr double GATHER_MARGIN = 0.05;
// A hull of more points than this is taken as its bounding box: finding its
// faces is cubic in the points.
constexpr int HULL_MAX_POINTS = 96;

const char *const TYPE_NAME[RopeShape::TYPE_COUNT] = {"box", "sphere", "capsule", "cylinder",
                                                      "convex", "concave", "other"};

// What a shape resource IS, read out of the server once.
struct ShapeData
{
    RopeShape::Type type = RopeShape::OTHER;
    Vector3 size;
    std::vector<Plane> hull;
    int triangles = 0;
};

// Keyed by the shape's RID. Written on the main thread (GatherShapes), read by
// the solves, which never run while a gather does. Entries are never moved
// (unordered_map keeps its nodes), so a RopeShape may point into one.
std::unordered_map<int64_t, ShapeData> g_shape_data;

// The faces of the convex hull of p_points, as planes pointing out. Every
// triple of points whose plane has all the others on one side is a face.
void hull_planes(const PackedVector3Array &p_points, std::vector<Plane> &r_planes)
{
    const int n = static_cast<int>(p_points.size());
    const auto add = [&](const Plane &p_plane) {
        for (const Plane &have : r_planes)
            if (have.normal.dot(p_plane.normal) > 0.9995 && std::abs(have.d - p_plane.d) < 1e-4)
                return;
        r_planes.push_back(p_plane);
    };
    for (int i = 0; i < n; ++i)
        for (int j = i + 1; j < n; ++j)
            for (int k = j + 1; k < n; ++k)
            {
                Vector3 normal = (p_points[j] - p_points[i]).cross(p_points[k] - p_points[i]);
                const double len = normal.length();
                if (len < 1e-10)
                    continue;
                normal /= len;
                const double d = normal.dot(p_points[i]);
                bool above = false;
                bool below = false;
                for (int m = 0; m < n && !(above && below); ++m)
                {
                    const double side = normal.dot(p_points[m]) - d;
                    above = above || side > 1e-5;
                    below = below || side < -1e-5;
                }
                if (above && below)
                    continue;
                add(above ? Plane(-normal, -d) : Plane(normal, d));
            }
}

const ShapeData &shape_data(PhysicsServer3D *ps, const RID &p_shape)
{
    const int64_t key = p_shape.get_id();
    const auto found = g_shape_data.find(key);
    if (found != g_shape_data.end())
        return found->second;
    ShapeData s;
    const Variant data = ps->shape_get_data(p_shape);
    const PhysicsServer3D::ShapeType type = ps->shape_get_type(p_shape);
    switch (type)
    {
    case PhysicsServer3D::SHAPE_BOX:
        s.type = RopeShape::BOX;
        s.size = data;
        break;
    case PhysicsServer3D::SHAPE_SPHERE:
        s.type = RopeShape::SPHERE;
        s.size.x = static_cast<double>(data);
        break;
    case PhysicsServer3D::SHAPE_CAPSULE:
    case PhysicsServer3D::SHAPE_CYLINDER:
    {
        const Dictionary d = data;
        const double radius = d.get("radius", 0.0);
        const double height = d.get("height", 0.0);
        const bool capsule = type == PhysicsServer3D::SHAPE_CAPSULE;
        s.type = capsule ? RopeShape::CAPSULE : RopeShape::CYLINDER;
        s.size.x = radius;
        // A capsule's height is tip to tip: its axis runs between cap centres.
        s.size.y = capsule ? std::max(0.0, height * 0.5 - radius) : height * 0.5;
        break;
    }
    case PhysicsServer3D::SHAPE_CONVEX_POLYGON:
    {
        const PackedVector3Array points = data;
        s.type = RopeShape::CONVEX;
        if (points.size() >= 4 && points.size() <= HULL_MAX_POINTS)
            hull_planes(points, s.hull);
        if (s.hull.size() < 4)
        {
            // Too many points, or flat: its bounding box stands in.
            s.hull.clear();
            Vector3 lo = points.size() > 0 ? points[0] : Vector3();
            Vector3 hi = lo;
            for (const Vector3 &p : points)
            {
                lo = lo.min(p);
                hi = hi.max(p);
            }
            s.hull = {Plane(Vector3(1, 0, 0), hi.x),  Plane(Vector3(-1, 0, 0), -lo.x),
                      Plane(Vector3(0, 1, 0), hi.y),  Plane(Vector3(0, -1, 0), -lo.y),
                      Plane(Vector3(0, 0, 1), hi.z),  Plane(Vector3(0, 0, -1), -lo.z)};
        }
        break;
    }
    case PhysicsServer3D::SHAPE_CONCAVE_POLYGON:
    {
        s.type = RopeShape::CONCAVE;
        const Dictionary d = data;
        const PackedVector3Array faces = d.get("faces", PackedVector3Array());
        s.triangles = static_cast<int>(faces.size() / 3);
        break;
    }
    default:
        break;
    }
    return g_shape_data.emplace(key, std::move(s)).first->second;
}

// A point against a shape, in the shape's own frame and units.
bool nearest_local(const RopeShape &s, const Vector3 &p, double &r_d, Vector3 &r_q, Vector3 &r_n)
{
    switch (s.type)
    {
    case RopeShape::BOX:
    {
        const Vector3 h = s.size;
        const Vector3 q(CLAMP(p.x, -h.x, h.x), CLAMP(p.y, -h.y, h.y), CLAMP(p.z, -h.z, h.z));
        const Vector3 out = p - q;
        const double len = out.length();
        if (len > 1e-9)
        {
            r_d = len;
            r_q = q;
            r_n = out / len;
            return true;
        }
        // Inside: out by the nearest face.
        const double dx = h.x - std::abs(p.x);
        const double dy = h.y - std::abs(p.y);
        const double dz = h.z - std::abs(p.z);
        r_q = p;
        if (dx <= dy && dx <= dz)
        {
            r_n = Vector3(p.x < 0.0 ? -1.0 : 1.0, 0, 0);
            r_q.x = r_n.x * h.x;
            r_d = -dx;
        }
        else if (dy <= dz)
        {
            r_n = Vector3(0, p.y < 0.0 ? -1.0 : 1.0, 0);
            r_q.y = r_n.y * h.y;
            r_d = -dy;
        }
        else
        {
            r_n = Vector3(0, 0, p.z < 0.0 ? -1.0 : 1.0);
            r_q.z = r_n.z * h.z;
            r_d = -dz;
        }
        return true;
    }
    case RopeShape::SPHERE:
    case RopeShape::CAPSULE:
    {
        const double half = s.type == RopeShape::CAPSULE ? s.size.y : 0.0;
        const Vector3 centre(0, CLAMP(p.y, -half, half), 0);
        const Vector3 out = p - centre;
        const double len = out.length();
        r_n = len > 1e-9 ? out / len : Vector3(1, 0, 0);
        r_d = len - s.size.x;
        r_q = centre + r_n * s.size.x;
        return true;
    }
    case RopeShape::CYLINDER:
    {
        const double radius = s.size.x;
        const double half = s.size.y;
        const double radial = std::sqrt(p.x * p.x + p.z * p.z);
        const Vector3 away = radial > 1e-9 ? Vector3(p.x / radial, 0, p.z / radial) : Vector3(1, 0, 0);
        const double over_side = radial - radius;
        const double over_end = std::abs(p.y) - half;
        if (over_side <= 0.0 && over_end <= 0.0)
        {
            // Inside: out by the side or the nearer end, whichever is closer.
            if (over_side > over_end)
            {
                r_n = away;
                r_d = over_side;
                r_q = away * radius + Vector3(0, p.y, 0);
            }
            else
            {
                r_n = Vector3(0, p.y < 0.0 ? -1.0 : 1.0, 0);
                r_d = over_end;
                r_q = Vector3(p.x, r_n.y * half, p.z);
            }
            return true;
        }
        const Vector3 q = away * std::min(radial, radius) + Vector3(0, CLAMP(p.y, -half, half), 0);
        const Vector3 out = p - q;
        const double len = out.length();
        r_n = len > 1e-9 ? out / len : away;
        r_d = len;
        r_q = q;
        return true;
    }
    case RopeShape::CONVEX:
    {
        if (s.hull == nullptr || s.hull->empty())
            return false;
        // The face it is furthest outside of (or least far inside). Exact
        // against a face; near an edge the cord stands off a little further
        // than its radius, as from a corner cut square and not round.
        double best = -1e30;
        const Plane *face = nullptr;
        for (const Plane &plane : *s.hull)
        {
            const double d = plane.normal.dot(p) - plane.d;
            if (d > best)
            {
                best = d;
                face = &plane;
            }
        }
        r_d = best;
        r_n = face->normal;
        r_q = p - face->normal * best;
        return true;
    }
    default:
        return false;
    }
}
// A segment that passes THROUGH a solid bounded by planes (a box, a hull), in
// the solid's own frame. Which way out is not the nearest face to any one
// point of it: across the 2 cm top of a panel that is a side, and a cord
// lying over the top was put out sideways, through the panel. It is the face
// by which the WHOLE piece inside gets out with the least travel. False when
// no part of the segment is inside.
bool segment_through(const Plane *p_planes, int p_count, const Vector3 &a, const Vector3 &b, double &r_t,
                     double &r_d, Vector3 &r_q, Vector3 &r_n)
{
    // The part of the segment inside every plane.
    double t0 = 0.0;
    double t1 = 1.0;
    const Vector3 ab = b - a;
    for (int k = 0; k < p_count; ++k)
    {
        const double da = p_planes[k].normal.dot(a) - p_planes[k].d;
        const double db = p_planes[k].normal.dot(b) - p_planes[k].d;
        if (da > 0.0 && db > 0.0)
            return false;
        if (da > 0.0)
            t0 = std::max(t0, da / (da - db));
        else if (db > 0.0)
            t1 = std::min(t1, da / (da - db));
        if (t0 >= t1)
            return false;
    }
    const Vector3 in0 = a + ab * t0;
    const Vector3 in1 = a + ab * t1;
    double least = 1e30;
    int face = -1;
    bool at_first = true;
    for (int k = 0; k < p_count; ++k)
    {
        // How far along this face's normal the deeper end of the piece is in.
        const double d0 = p_planes[k].normal.dot(in0) - p_planes[k].d;
        const double d1 = p_planes[k].normal.dot(in1) - p_planes[k].d;
        const double depth = -std::min(d0, d1);
        if (depth < least)
        {
            least = depth;
            face = k;
            at_first = d0 <= d1;
        }
    }
    if (face < 0 || least < 1e-7)
        return false;
    r_t = at_first ? t0 : t1;
    r_n = p_planes[face].normal;
    r_d = -least;
    const Vector3 deep = at_first ? in0 : in1;
    r_q = deep + r_n * least;
    return true;
}
} // namespace

bool rope_nearest_on_shape(const RopeShape &p_shape, const Vector3 &p_world, RopeNearest &r_out)
{
    const Vector3 local = p_shape.to_local.xform(p_world) / p_shape.scale;
    double d = 0.0;
    Vector3 q;
    Vector3 n;
    if (!nearest_local(p_shape, local, d, q, n))
        return false;
    r_out.distance = d * p_shape.scale;
    r_out.point = p_shape.to_world.xform(q * p_shape.scale);
    r_out.normal = p_shape.to_world.basis.xform(n);
    return true;
}

// Every shape here is convex, so the distance from the shape is a convex
// function along the segment and stepping between "nearest point of the shape"
// and "nearest point of the segment to that" walks down to its one minimum.
bool rope_segment_nearest_on_shape(const RopeShape &p_shape, const Vector3 &p_a, const Vector3 &p_b,
                                   double &r_t, RopeNearest &r_out)
{
    const Vector3 a = p_shape.to_local.xform(p_a) / p_shape.scale;
    const Vector3 b = p_shape.to_local.xform(p_b) / p_shape.scale;
    const Vector3 ab = b - a;
    const double length_sq = ab.length_squared();
    double t = 0.5;
    double d = 0.0;
    Vector3 q;
    Vector3 n;
    bool through = false;
    if (p_shape.type == RopeShape::BOX)
    {
        const Vector3 h = p_shape.size;
        const Plane faces[6] = {Plane(Vector3(1, 0, 0), h.x),  Plane(Vector3(-1, 0, 0), h.x),
                                Plane(Vector3(0, 1, 0), h.y),  Plane(Vector3(0, -1, 0), h.y),
                                Plane(Vector3(0, 0, 1), h.z),  Plane(Vector3(0, 0, -1), h.z)};
        through = segment_through(faces, 6, a, b, t, d, q, n);
    }
    else if (p_shape.type == RopeShape::CONVEX && p_shape.hull != nullptr && !p_shape.hull->empty())
        through = segment_through(p_shape.hull->data(), static_cast<int>(p_shape.hull->size()), a, b, t, d, q, n);
    for (int step = 0; step < 10 && !through; ++step)
    {
        if (!nearest_local(p_shape, a + ab * t, d, q, n))
            return false;
        if (d <= 0.0 || length_sq < 1e-12)
            break;
        const double next = CLAMP((q - a).dot(ab) / length_sq, 0.0, 1.0);
        if (std::abs(next - t) < 1e-4)
            break;
        t = next;
    }
    r_t = t;
    r_out.distance = d * p_shape.scale;
    r_out.point = p_shape.to_world.xform(q * p_shape.scale);
    r_out.normal = p_shape.to_world.basis.xform(n);
    return true;
}

// Where a point that went from p_from to p_to met the shape on the way: the
// surface it came in by. A point found inside a shape is not asked which face
// is NEAREST (through a thin panel that is the far one, and it would be put
// out on the wrong side): it is put back out by the face it crossed. Walked in
// steps no longer than p_step, so a fast point cannot step clean over a panel.
// False when it never touched, or began inside already.
bool rope_way_in(const RopeShape &p_shape, const Vector3 &p_from, const Vector3 &p_to, double p_step,
                 double p_touch, RopeNearest &r_out)
{
    RopeNearest was;
    if (!rope_nearest_on_shape(p_shape, p_from, was) || was.distance < 0.0)
        return false;
    const double travel = p_from.distance_to(p_to);
    const int steps = CLAMP(static_cast<int>(std::ceil(travel / std::max(p_step, 1e-4))), 1, 24);
    RopeNearest now;
    for (int k = 1; k <= steps; ++k)
    {
        const Vector3 at = p_from.lerp(p_to, static_cast<double>(k) / steps);
        if (!rope_nearest_on_shape(p_shape, at, now))
            return false;
        if (now.distance < p_touch)
        {
            // The last place it was clear of the surface says which face.
            r_out = now.distance < 0.0 ? was : now;
            return true;
        }
        was = now;
    }
    return false;
}

// The bodies whose bounds meet a box round the whole cord, each shape read out
// of the physics server into m_near. One query, however long the cord is.
void VerletRope::GatherShapes(PhysicsDirectSpaceState3D *p_space)
{
    m_near.clear();
    PhysicsServer3D *ps = PhysicsServer3D::get_singleton();
    if (ps == nullptr || p_space == nullptr || m_points.empty() || m_surface_collision_mask == 0)
        return;
    if (!m_gather_box.is_valid())
        m_gather_box = ps->box_shape_create();
    if (m_gather_query.is_null())
    {
        m_gather_query.instantiate();
        m_gather_query->set_shape_rid(m_gather_box);
        m_gather_query->set_collision_mask(m_surface_collision_mask);
        if (m_ray_query.is_valid())
            m_gather_query->set_exclude(m_ray_query->get_exclude());
    }

    Vector3 lo = m_points[0];
    Vector3 hi = m_points[0];
    for (const Vector3 &p : m_points)
    {
        lo = lo.min(p);
        hi = hi.max(p);
    }
    const double pad = m_collision_radius + GATHER_MARGIN;
    const Vector3 half = (hi - lo) * 0.5 + Vector3(pad, pad, pad);
    ps->shape_set_data(m_gather_box, half);
    m_gather_query->set_transform(Transform3D(Basis(), (lo + hi) * 0.5));

    const TypedArray<Dictionary> found = p_space->intersect_shape(m_gather_query, GATHER_MAX);
    const int count = static_cast<int>(found.size());
    if (count >= GATHER_MAX && !m_gather_full_logged)
    {
        m_gather_full_logged = true;
        UtilityFunctions::print("[Rope] ", get_path(), ": ", GATHER_MAX,
                                " or more shapes near this cord; the rest are not seen");
    }
    m_near.reserve(count);
    // A shape's bounds are grown by how far a contact reaches
    // (ContactsFromShapes) and a little: a point outside them is skipped, and
    // one skipped while still in reach has no plane at all.
    const double reach = ContactReach() + 0.005;
    for (int k = 0; k < count; ++k)
    {
        const Dictionary hit = found[k];
        const RID body = hit["rid"];
        const int index = hit["shape"];
        if (!body.is_valid())
            continue;
        const RID shape = ps->body_get_shape(body, index);
        if (!shape.is_valid())
            continue;
        const ShapeData &data = shape_data(ps, shape);
        RopeShape s;
        s.type = data.type;
        s.size = data.size;
        s.hull = data.type == RopeShape::CONVEX ? &data.hull : nullptr;
        s.triangles = data.triangles;
        s.body = static_cast<uint64_t>(body.get_id());
        s.shape = shape.get_id();
        const Transform3D body_xf = ps->body_get_state(body, PhysicsServer3D::BODY_STATE_TRANSFORM);
        Transform3D frame = body_xf * ps->body_get_shape_transform(body, index);
        // The scale is taken out of the frame and kept beside it.
        const double det = frame.basis.determinant();
        s.scale = std::abs(det) > 1e-12 ? std::cbrt(std::abs(det)) : 1.0;
        frame.basis = frame.basis.orthonormalized();
        s.to_world = frame;
        s.to_local = frame.affine_inverse();
        // Bounds in the world, from the shape's own extent.
        Vector3 extent;
        switch (s.type)
        {
        case RopeShape::BOX:
            extent = s.size;
            break;
        case RopeShape::SPHERE:
            extent = Vector3(s.size.x, s.size.x, s.size.x);
            break;
        case RopeShape::CAPSULE:
            extent = Vector3(s.size.x, s.size.y + s.size.x, s.size.x);
            break;
        case RopeShape::CYLINDER:
            extent = Vector3(s.size.x, s.size.y, s.size.x);
            break;
        default:
            extent = Vector3(1e6, 1e6, 1e6);
            break;
        }
        if (s.type == RopeShape::CONVEX || extent.x > 1e5)
        {
            s.lo = Vector3(-1e9, -1e9, -1e9);
            s.hi = Vector3(1e9, 1e9, 1e9);
        }
        else
        {
            extent *= s.scale;
            const Basis &m = frame.basis;
            const Vector3 world_extent(
                    std::abs(m[0][0]) * extent.x + std::abs(m[0][1]) * extent.y + std::abs(m[0][2]) * extent.z,
                    std::abs(m[1][0]) * extent.x + std::abs(m[1][1]) * extent.y + std::abs(m[1][2]) * extent.z,
                    std::abs(m[2][0]) * extent.x + std::abs(m[2][1]) * extent.y + std::abs(m[2][2]) * extent.z);
            const Vector3 grow(reach, reach, reach);
            s.lo = frame.origin - world_extent - grow;
            s.hi = frame.origin + world_extent + grow;
        }
        m_near.push_back(s);
    }
}

// The contact planes of this slice, straight from the shapes: for every free
// particle and every segment, the surfaces within reach, the two that bear
// most and face different ways. Written into the arrays the solver, the
// friction and the resting tests already read. Pure: m_near and the cord.
void VerletRope::ContactsFromShapes()
{
    const int count = static_cast<int>(m_points.size());
    const int seg_count = static_cast<int>(m_seg_a.size());
    std::fill(m_c_flags.begin(), m_c_flags.end(), 0);
    std::fill(m_mid_contact.begin(), m_mid_contact.end(), 0);
    if (m_near.empty())
        return;
    // A surface this near gets a plane. Well past touching: a plane is a limit
    // and costs nothing until it is met, and one that is only made once the
    // cord already touches is too late for a cord pulled hard, which travels
    // further than its own radius inside one slice.
    const double reach = ContactReach();
    const bool have_from = m_tick_from.size() == m_points.size();
    RopeNearest at;
    for (int i = 0; i < count; ++i)
    {
        if (m_inv_mass[i] == 0.0f)
            continue;
        const Vector3 p = m_points[i];
        double d1 = reach;
        double d2 = reach;
        for (RopeShape &shape : m_near)
        {
            if (p.x < shape.lo.x || p.y < shape.lo.y || p.z < shape.lo.z || p.x > shape.hi.x ||
                p.y > shape.hi.y || p.z > shape.hi.z)
                continue;
            if (!rope_nearest_on_shape(shape, p, at))
                continue;
            // Inside it, or moved far enough this tick to have gone through
            // it: the face it came in by, not the one it is nearest now.
            if (have_from && (at.distance < 0.0 ||
                              m_tick_from[i].distance_squared_to(p) > m_collision_radius * m_collision_radius))
            {
                RopeNearest in;
                if (rope_way_in(shape, m_tick_from[i], p, m_collision_radius, m_collision_radius, in))
                {
                    at.point = in.point;
                    at.normal = in.normal;
                    at.distance = (p - in.point).dot(in.normal);
                }
            }
            if (at.distance >= d2)
                continue;
            if (at.distance < m_collision_radius * 1.3)
                shape.touched = true;
            if (at.distance < d1)
            {
                // The old first becomes the second, if it faces another way.
                if ((m_c_flags[i] & 1) && m_c_n1[i].dot(at.normal) < 0.9)
                {
                    m_c_p2[i] = m_c_p1[i];
                    m_c_n2[i] = m_c_n1[i];
                    d2 = d1;
                    m_c_flags[i] |= 2;
                }
                m_c_p1[i] = at.point;
                m_c_n1[i] = at.normal;
                d1 = at.distance;
                m_c_flags[i] |= 1;
            }
            else if (m_c_n1[i].dot(at.normal) < 0.9)
            {
                m_c_p2[i] = at.point;
                m_c_n2[i] = at.normal;
                d2 = at.distance;
                m_c_flags[i] |= 2;
            }
        }
    }
    for (int s = 0; s < seg_count; ++s)
    {
        const int ia = m_seg_a[s];
        const int ib = m_seg_b[s];
        if (m_inv_mass[ia] + m_inv_mass[ib] == 0.0f)
            continue;
        const Vector3 a = m_points[ia];
        const Vector3 b = m_points[ib];
        const Vector3 lo = a.min(b);
        const Vector3 hi = a.max(b);
        double d1 = reach;
        double d2 = reach;
        for (RopeShape &shape : m_near)
        {
            if (hi.x < shape.lo.x || hi.y < shape.lo.y || hi.z < shape.lo.z || lo.x > shape.hi.x ||
                lo.y > shape.hi.y || lo.z > shape.hi.z)
                continue;
            double t = 0.5;
            if (!rope_segment_nearest_on_shape(shape, a, b, t, at))
                continue;
            // At an end of the segment the particle there has it already
            // (unless the segment is INSIDE: then the end is the deep one).
            if (at.distance >= 0.0 &&
                ((t < 0.02 && m_inv_mass[ia] != 0.0f) || (t > 0.98 && m_inv_mass[ib] != 0.0f)))
                continue;
            if (have_from && at.distance < 0.0 && shape.type != RopeShape::BOX && shape.type != RopeShape::CONVEX)
            {
                // That point of the segment is inside: by the face it crossed.
                const Vector3 from = m_tick_from[ia].lerp(m_tick_from[ib], t);
                const Vector3 to = a.lerp(b, t);
                RopeNearest in;
                if (rope_way_in(shape, from, to, m_collision_radius, m_collision_radius, in))
                {
                    at.point = in.point;
                    at.normal = in.normal;
                    at.distance = (to - in.point).dot(in.normal);
                }
            }
            // A segment may bear on one shape in TWO places: across the 2 cm
            // top of a panel it lies on both edges, and held at one alone it
            // pivots there and its other end goes in. So the surface is asked
            // after toward each end as well, and a place far enough along from
            // the first is a second contact even when it faces the same way.
            // (Tried and worse, 2026-11-17: taking only places that face the
            // way the first does, and asking a box's twelve edges each for
            // itself. The thin panel under a slow pull depends on this as it
            // is; the same panel under a yank is still lost.)
            const auto offer = [&](double p_t, const RopeNearest &p_at) {
                if (p_at.distance >= d2)
                    return;
                if (p_at.distance < m_collision_radius * 1.3)
                    shape.touched = true;
                const bool apart = (m_mid_contact[s] & 1) &&
                                   (m_mid_contact_normal[s].dot(p_at.normal) < 0.9 ||
                                    std::abs(m_mid_contact_t[s] - p_t) > 0.3);
                if (p_at.distance < d1)
                {
                    if (apart)
                    {
                        m_mid_contact_point_2[s] = m_mid_contact_point[s];
                        m_mid_contact_normal_2[s] = m_mid_contact_normal[s];
                        m_mid_contact_t_2[s] = m_mid_contact_t[s];
                        d2 = d1;
                        m_mid_contact[s] |= 2;
                    }
                    m_mid_contact_point[s] = p_at.point;
                    m_mid_contact_normal[s] = p_at.normal;
                    m_mid_contact_t[s] = static_cast<float>(p_t);
                    d1 = p_at.distance;
                    m_mid_contact[s] |= 1;
                }
                else if (apart)
                {
                    m_mid_contact_point_2[s] = p_at.point;
                    m_mid_contact_normal_2[s] = p_at.normal;
                    m_mid_contact_t_2[s] = static_cast<float>(p_t);
                    d2 = p_at.distance;
                    m_mid_contact[s] |= 2;
                }
            };
            offer(t, at);
            for (const double toward : {0.15, 0.85})
            {
                if (std::abs(toward - t) < 0.3)
                    continue;
                RopeNearest there;
                if (rope_nearest_on_shape(shape, a.lerp(b, toward), there) && there.distance >= 0.0)
                    offer(toward, there);
            }
        }
    }
}

// What a sleeping cord watches, kept as it falls asleep: the shapes it bore on.
void VerletRope::RememberSupports()
{
    m_sleep_supports.clear();
    for (const RopeShape &shape : m_near)
        if (shape.touched)
            m_sleep_supports.push_back(shape);
}

// Whether the room has changed under a sleeping cord: something it lay on has
// moved or gone, or something has come to be in it. One gather; no rays.
bool VerletRope::ShapesChangedWhileSleeping(PhysicsDirectSpaceState3D *p_space)
{
    GatherShapes(p_space);
    for (const RopeShape &was : m_sleep_supports)
    {
        bool still = false;
        for (const RopeShape &now : m_near)
        {
            if (now.body != was.body || now.shape != was.shape)
                continue;
            still = now.to_world.origin.distance_squared_to(was.to_world.origin) < 1e-6 &&
                    now.to_world.basis.get_column(0).dot(was.to_world.basis.get_column(0)) > 0.99999 &&
                    now.to_world.basis.get_column(1).dot(was.to_world.basis.get_column(1)) > 0.99999;
            break;
        }
        if (!still)
            return true;
    }
    // Something new in the cord itself: a body put down on it.
    RopeNearest at;
    for (const RopeShape &now : m_near)
    {
        bool known = false;
        for (const RopeShape &was : m_sleep_supports)
            known = known || (was.body == now.body && was.shape == now.shape);
        if (known)
            continue;
        for (size_t i = 0; i < m_points.size(); ++i)
        {
            if (m_inv_mass[i] == 0.0f)
                continue;
            if (rope_nearest_on_shape(now, m_points[i], at) && at.distance < m_collision_radius * 0.5)
                return true;
        }
    }
    return false;
}

// XENU_ROPE_CENSUS=1: what each cord has near it, by kind of shape, said when
// it changes. The count the collision plan's choices rest on.
void VerletRope::CensusShapes(PhysicsDirectSpaceState3D *p_space)
{
    if (++m_census_tick < 90)
        return;
    m_census_tick = 0;
    if (m_collision_mode == 0)
        GatherShapes(p_space);
    int kinds[RopeShape::TYPE_COUNT] = {};
    int triangles = 0;
    for (const RopeShape &s : m_near)
    {
        kinds[s.type] += 1;
        triangles += s.triangles;
    }
    String line;
    for (int t = 0; t < RopeShape::TYPE_COUNT; ++t)
        if (kinds[t] > 0)
            line += String::num_int64(kinds[t]) + " " + TYPE_NAME[t] + " ";
    if (triangles > 0)
        line += "(" + String::num_int64(triangles) + " triangles) ";
    if (line.is_empty())
        line = "nothing ";
    if (line == m_census_last)
        return;
    m_census_last = line;
    UtilityFunctions::print("[Rope] census ", get_path(), ": ", line, "near ",
                            static_cast<int>(m_points.size()), " particles");
}

void VerletRope::FreeGatherShape()
{
    if (!m_gather_box.is_valid())
        return;
    if (PhysicsServer3D *ps = PhysicsServer3D::get_singleton())
        ps->free_rid(m_gather_box);
    m_gather_box = RID();
}

} // namespace Xenu
