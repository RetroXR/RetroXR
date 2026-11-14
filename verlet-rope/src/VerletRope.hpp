#pragma once

// Verlet rope — PBD rope simulation between two 3D anchor points. Ported from
// Scripts/Objects/cables/verlet_rope.gd, which this replaces; the GDScript
// version was the single largest CPU item in a scene full of cables (~460 us
// per rope per physics tick plus ~157 us per rendered frame to re-mesh the
// tube), and essentially all of that was interpreter overhead in the solver's
// inner loops rather than real work.
//
// It began as that script's solver, constraint for constraint. Since
// 2026-11-10 it is not: a tick is SUBSTEPS slices (4), each a short integration
// and a share of the iterations, and the cord's contacts with itself are solved
// inside the loop with the rest (docs/dev/rope.md, "Substeps"). The environment
// is still asked once a tick.
//
// Constraints, in solve order:
//   - Stretch: distance constraints between neighbours (stretch_stiffness).
//   - Bend: hierarchical, toward the midpoint of neighbours at spacing 1/2/4…,
//     with a max_bend_degrees free allowance.
//   - End stiffness: a strain-relief stub holding the first/last few segments
//     straight, plus a directional stub for an end whose plug orientation is
//     externally fixed.
//   - The cord against itself: particle pairs and segment pairs found once a
//     tick, inelastic, with the same Coulomb friction strand on strand.
//   - Cached contact planes, per particle and per segment midpoint, with
//     Coulomb friction (static_friction / kinetic_friction) on velocity, sized
//     by how hard the planes pushed back. A plane is kept only while a ray
//     finds its face under the particle, and a segment lying over a sharp EDGE
//     holds the edge's line, not a plane.
//
// A loose plug is a real RigidBody3D that Jolt owns. The rope never moves it
// directly: the corrections the solver makes against a pinned end (the last
// segment's tension, the boot pulling the cord onto the plug's exit axis) are
// turned into a force and a torque on that body, sized by linear_density. The
// plug in turn drives the rope, which stays pinned to its cord boss.
//
// ── Ribbon cables ───────────────────────────────────────────────────────────
// ribbon_count > 1 draws the rope as several cords moulded side by side in a
// flat ribbon ("ooo"), the shape a composite A/V lead actually has. The cords
// cannot be pulled apart, so the trunk stays ONE simulated chain and the extra
// cords are extra tubes offset laterally in its transport frame — N surfaces on
// one ArrayMesh, one material each. Simulating the trunk N times would cost N
// times as much and still shimmer, because a PBD glue constraint is never
// exactly rigid.
//
// At a fray the ribbon splits by DESTINATION, not by cord: every cord heading
// for the same plug shares one chain and stays moulded together as a narrower
// ribbon all the way in. Those chains hang off the trunk's terminal particle,
// which is left free so the junction behaves like the unsupported breakout of a
// real cable. fray_end_groups = [0, 0, 1] on a 3-cord ribbon sends cords 0 and 1
// to plug 0 as a 2-wide ribbon and cord 2 to plug 1 alone.
//
// The particles all live in one flat array — trunk first, then each fray chain —
// so every per-particle pass (integrate, friction, self-collision, the surface
// rays, sleep, render snapshot) is unchanged. Only adjacency-aware code needs
// the m_seg_* segment table and the m_fray chain table below.

#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/capsule_shape3d.hpp>
#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/physics_point_query_parameters3d.hpp>
#include <godot_cpp/classes/physics_ray_query_parameters3d.hpp>
#include <godot_cpp/classes/physics_shape_query_parameters3d.hpp>
#include <godot_cpp/classes/rigid_body3d.hpp>
#include <godot_cpp/classes/shader.hpp>
#include <godot_cpp/classes/shader_material.hpp>
#include <godot_cpp/classes/sphere_shape3d.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

#include <cstdint>
#include <unordered_map>
#include <vector>

namespace Xenu
{

class VerletRope : public godot::MeshInstance3D
{
    GDCLASS(VerletRope, godot::MeshInstance3D)

public:
    // Endpoint authority is explicit at the rope boundary. AUTO preserves old
    // scenes by deriving the live state from the node, while authored roles let
    // callers state the contract without relying on RigidBody freeze/pickup
    // implementation details.
    enum EndpointRole
    {
        ENDPOINT_AUTO = 0,
        ENDPOINT_HOST,
        ENDPOINT_FREE_PLUG,
        ENDPOINT_HELD_PLUG,
        ENDPOINT_SOCKETED_PLUG,
    };

    VerletRope() = default;
    ~VerletRope() override;

    void _ready() override;
    void _process(double p_delta) override;
    void _physics_process(double p_delta) override;
    void _enter_tree() override;
    void _exit_tree() override;
    // Joins the solve workers. Called when the extension unloads.
    static void ShutdownSolveWorkers();

    // One simulation tick. Bound so a bench can drive the rope off the engine's
    // callback and time it directly; _physics_process is just this plus the
    // engine's cadence.
    void Step(double p_delta);
    // Render-time interpolation plus the tube rebuild — the body of _process,
    // bound for the same reason as Step.
    void Remesh();
    bool IsSleeping() const { return m_asleep; }

    // ── Public API used from GDScript ────────────────────────────────────────
    void InitPoints();
    void Wake();
    // Where the player is (the camera), set once a frame from script: a sleeping cord far from it polls its
    // supports less often (SLEEP_ENVIRONMENT_FAR). Never set, every cord polls at the near rate.
    static void SetFocus(const godot::Vector3 &p_position);
    // How much of a sleeping cord one environment poll looks at: 1 (the
    // default) all of it, n one particle and segment in n, a different share
    // each poll. For a device where the polls of a room of cords cost frames.
    static void SetSleepPollStride(int p_stride);
    static int GetSleepPollStride() { return s_sleep_poll_stride; }
    static int s_sleep_poll_stride;
    static godot::Vector3 s_focus;
    static bool s_has_focus;
    double RestLength() const;
    godot::PackedVector3Array GetPoints() const;
    bool RestorePoints(const godot::PackedVector3Array &p_points);
    godot::Dictionary GetSleepMetrics() const;
    godot::Dictionary GetContactDebug(int p_index) const;
    void NudgePoint(int p_index, const godot::Vector3 &p_delta);

    /// How many particles the cord is made of, and where one of them is in
    /// world space. Read-only counterparts to NudgePoint, for anything that has
    /// to RIDE a cord rather than pull on it — the moulded junction partway
    /// along a GBA link cable being the case this was added for. Returns the
    /// zero vector for an index off the end rather than faulting, because the
    /// particle count changes with segment_count and a caller that cached one
    /// should get a harmless answer.
    int PointCount() const;
    godot::Vector3 PointPosition(int p_index) const;
    void SetRopeLength(double p_length);

    /// A hand on the cord, partway along it. `closest_point` finds the spot on
    /// the trunk nearest a world position ({index, position, distance, along,
    /// length}; index -1 for a cord with nothing to take). `hold_point` pins
    /// that particle to a world position the caller then moves with
    /// `move_hold`; `release_hold` lets it go with the velocity the hand had.
    /// A held particle is a pin like the cord's ends (inverse mass 0), carried
    /// to its target over the tick's slices. A pinned end cannot be held.
    godot::Dictionary ClosestPoint(const godot::Vector3 &p_world) const;
    godot::Dictionary ClosestPointToRay(const godot::Vector3 &p_origin, const godot::Vector3 &p_dir,
                                        double p_reach) const;
    bool HoldPoint(int p_index, const godot::Vector3 &p_world);
    void MoveHold(int p_index, const godot::Vector3 &p_world);
    void ReleaseHold(int p_index);
    bool IsHeld(int p_index) const;
    int HoldCount() const { return static_cast<int>(m_holds.size()); }

    // Anchors. Held as ObjectIDs rather than raw pointers: a plug or a host
    // machine can be freed while the rope still exists, and a stale Node3D* here
    // is a crash rather than a missing cable.
    void SetStartNode(godot::Node3D *p_node);
    godot::Node3D *GetStartNode() const;
    void SetEndNode(godot::Node3D *p_node);
    godot::Node3D *GetEndNode() const;

    // ── Exported properties ──────────────────────────────────────────────────
#define XENU_ROPE_PROP(type, name, member)                                     \
    void Set##name(type v) { member = v; }                                     \
    type Get##name() const { return member; }

    XENU_ROPE_PROP(int, SegmentCount, m_segment_count)
    XENU_ROPE_PROP(godot::Vector3, Gravity, m_gravity)
    XENU_ROPE_PROP(double, Damping, m_damping)
    XENU_ROPE_PROP(int, ConstraintIterations, m_constraint_iterations)
    XENU_ROPE_PROP(double, StretchStiffness, m_stretch_stiffness)
    XENU_ROPE_PROP(double, BendStiffness, m_bend_stiffness)
    XENU_ROPE_PROP(double, StretchCompliance, m_stretch_compliance)
    XENU_ROPE_PROP(double, BendCompliance, m_bend_compliance)
    XENU_ROPE_PROP(double, ContactCompliance, m_contact_compliance)
    XENU_ROPE_PROP(double, MaxBendDegrees, m_max_bend_degrees)
    XENU_ROPE_PROP(double, BendStiffenDegrees, m_bend_stiffen_degrees)
    XENU_ROPE_PROP(double, BendLimitDegrees, m_bend_limit_degrees)
    XENU_ROPE_PROP(double, TubeRadius, m_tube_radius)
    XENU_ROPE_PROP(int, TubeSides, m_tube_sides)
    XENU_ROPE_PROP(int, Smoothing, m_smoothing)
    XENU_ROPE_PROP(int, SurfaceCollisionMask, m_surface_collision_mask)
    XENU_ROPE_PROP(double, CollisionRadius, m_collision_radius)
    XENU_ROPE_PROP(double, SurfaceFriction, m_surface_friction)
    XENU_ROPE_PROP(double, StaticFriction, m_static_friction)
    XENU_ROPE_PROP(double, KineticFriction, m_kinetic_friction)
    XENU_ROPE_PROP(double, LinearDensity, m_linear_density)
    XENU_ROPE_PROP(int, RaycastInterval, m_raycast_interval)
    XENU_ROPE_PROP(int, Substeps, m_substeps)
    XENU_ROPE_PROP(int, DebugDisable, m_debug_disable)
    XENU_ROPE_PROP(double, WaveDamping, m_wave_damping)
    XENU_ROPE_PROP(bool, SelfCollision, m_self_collision)
    XENU_ROPE_PROP(double, AnchorPull, m_anchor_pull)
    XENU_ROPE_PROP(double, EndAlignStiffness, m_end_align_stiffness)
    // Legacy whole-rope alias. Setting it updates both ends so old scenes keep
    // their exact behaviour; new code should author the two axes independently.
    void SetPlugExitAxis(const godot::Vector3 &v)
    {
        m_start_exit_axis = v;
        m_end_exit_axis = v;
    }
    godot::Vector3 GetPlugExitAxis() const { return m_end_exit_axis; }
    XENU_ROPE_PROP(godot::Vector3, StartExitAxis, m_start_exit_axis)
    XENU_ROPE_PROP(godot::Vector3, EndExitAxis, m_end_exit_axis)
    XENU_ROPE_PROP(int, StartEndpointRole, m_start_endpoint_role)
    XENU_ROPE_PROP(int, EndEndpointRole, m_end_endpoint_role)
    XENU_ROPE_PROP(godot::Vector3, StartAnchorOffset, m_start_anchor_offset)
    XENU_ROPE_PROP(godot::Vector3, EndAnchorOffset, m_end_anchor_offset)
    XENU_ROPE_PROP(double, EndStiffness, m_end_stiffness)
    XENU_ROPE_PROP(int, EndStiffSegments, m_end_stiff_segments)

    XENU_ROPE_PROP(double, RibbonSpacing, m_ribbon_spacing)
    XENU_ROPE_PROP(godot::Vector3, RibbonAxis, m_ribbon_axis)
    XENU_ROPE_PROP(int, FraySegmentsStart, m_fray_segments_start)
    XENU_ROPE_PROP(int, FraySegmentsEnd, m_fray_segments_end)
    XENU_ROPE_PROP(int, FrayTaperSegments, m_fray_taper_segments)
    XENU_ROPE_PROP(godot::PackedInt32Array, FrayStartGroups, m_fray_start_groups)
    XENU_ROPE_PROP(godot::PackedInt32Array, FrayEndGroups, m_fray_end_groups)
#undef XENU_ROPE_PROP

    // The two segment lengths are not plain setters: the solver reads its rest
    // distances out of the m_seg_rest table, so changing a length without
    // refreshing it leaves the rope solving to its old size. set_rope_length()
    // is called mid-flight (rope_stress's "rope_length halved" case) and silently
    // did nothing until this existed.
    void SetSegmentLength(double p_length);
    double GetSegmentLength() const { return m_segment_length; }
    void SetFraySegmentLength(double p_length);
    double GetFraySegmentLength() const { return m_fray_segment_length; }

    void SetRopeColor(const godot::Color &p_color);
    godot::Color GetRopeColor() const { return m_rope_color; }

    void SetRibbonCount(int p_count);
    int GetRibbonCount() const { return m_ribbon_count; }
    void SetRibbonColors(const godot::PackedColorArray &p_colors);
    godot::PackedColorArray GetRibbonColors() const { return m_ribbon_colors; }

    // Fray anchors, one per GROUP rather than per cord — cords that share a plug
    // share a chain. Settable before _init_points, like start_node/end_node.
    void SetFrayStartNode(int p_group, godot::Node3D *p_node);
    godot::Node3D *GetFrayStartNode(int p_group) const;
    void SetFrayEndNode(int p_group, godot::Node3D *p_node);
    godot::Node3D *GetFrayEndNode(int p_group) const;
    void SetFrayStartAnchorOffset(int p_group, const godot::Vector3 &p_offset);
    void SetFrayEndAnchorOffset(int p_group, const godot::Vector3 &p_offset);
    godot::Vector3 GetFrayStartPoint(int p_group) const;
    godot::Vector3 GetFrayEndPoint(int p_group) const;

protected:
    static void _bind_methods();

private:
    // One frayed branch: a chain shared by every cord bound for the same plug.
    // It hangs off `head`, a particle owned by the trunk, and owns `count`
    // particles starting at `first`; the last of those is pinned to the plug.
    struct FrayChain
    {
        int head = -1;
        int first = 0;
        int count = 0;
        bool at_start = false;
        uint64_t node_id = 0;
        godot::Vector3 offset;
        godot::Node3D *cached = nullptr;
        // The plug's rigidbody ancestor, if it has one — anchor_pull needs it to
        // drag a loose plug when its branch runs out of slack.
        godot::RigidBody3D *body = nullptr;
        godot::Vector3 sleep_pos;
        // Mean trunk slot of the cords in this group, in pitches. Only used to
        // seed an UNANCHORED branch off to the side: two anchorless branches
        // hung from the same junction are otherwise seeded identically, fall
        // identically forever, and self-collision cannot part them because its
        // divide-by-zero guard skips exactly-coincident pairs.
        float lat_mean = 0.0f;
        // Read on the main thread before a solve (the solve asks nothing of
        // the engine): whether this branch's plug holds a directional stub,
        // and along what.
        bool stub = false;
        godot::Vector3 stub_exit;
    };

    // ── Simulation ───────────────────────────────────────────────────────────
    // A tick in three parts, so that the middle one can run on a worker:
    // StepBegin reads the anchors and everything else the engine has to be
    // asked (false: nothing to solve this tick), StepSolve is arithmetic on
    // this cord's own arrays and nothing else, StepEnd asks the physics world
    // and pushes the plugs. Step() is the three in a row.
    bool StepBegin(double p_delta);
    void StepSolve();
    void StepEnd();
    static void RunBatch(double p_delta, uint64_t p_frame);
    void Integrate(double p_delta);
    double SliceStiffness(double p_k) const;
    void SolveConstraints(bool p_start_fixed, bool p_end_fixed,
                          const godot::Vector3 &p_start_exit,
                          const godot::Vector3 &p_end_exit);
    void ApplyContactFriction();
    // Self-collision: found once a tick, solved inside the constraint loop with
    // everything else, and made inelastic afterwards.
    void DetectSelfContacts();
    inline void SolveSelfContacts();
    void FinishSelfContacts();
    bool RestingNormal(int i, godot::Vector3 &r_normal) const;
    bool PushesIntoRest(int i, const godot::Vector3 &d) const;
    void SolveSurfaceCollision(bool p_do_rest);
    // The three phases of SolveSurfaceCollision, in the order it runs them.
    // Split out for reading only: the arithmetic and its order are unchanged,
    // which is what lets the bit-exact rope oracles keep gating this file.
    void SweepParticleContacts(godot::PhysicsDirectSpaceState3D *p_space, bool p_do_rest);
    void SolveSegmentCollision(godot::PhysicsDirectSpaceState3D *p_space, bool p_do_rest);
    void RecoverWrongSideParticles(godot::PhysicsDirectSpaceState3D *p_space);
    void KeepTautOutside(godot::PhysicsDirectSpaceState3D *p_space);
    void FindCrossings(godot::PhysicsDirectSpaceState3D *p_space);
    void EaseCrossings(godot::PhysicsDirectSpaceState3D *p_space);
    bool SurfaceUnder(godot::PhysicsDirectSpaceState3D *p_space, const godot::Vector3 &p_from,
                      double p_reach, godot::Vector3 &r_point, godot::Vector3 &r_normal);
    // Edge contacts (see m_edge_point).
    void UpdateEdgeContacts();
    bool PlaceEdgeContact(int s);
    bool EdgeParam(int s, const godot::Vector3 &p_point, const godot::Vector3 &p_dir,
                   double &r_t) const;
    void FindEdgeFor(godot::PhysicsDirectSpaceState3D *p_space, int i,
                     const godot::Vector3 &p_point, const godot::Vector3 &p_normal);
    bool EdgeStillThere(godot::PhysicsDirectSpaceState3D *p_space, int s);
    bool PlaneSupported(godot::PhysicsDirectSpaceState3D *p_space, int i, godot::Vector3 &r_point,
                        godot::Vector3 &r_normal);
    // Which cached contact slot a freshly reported plane belongs in: 1, 2, or 0
    // to keep both slots as they are.
    int ChooseContactSlot(int i, const godot::Vector3 &p_point, const godot::Vector3 &p_normal,
                          bool p_keep1, bool p_keep2) const;
    void AssignContactSlot(int i, int p_slot, const godot::Vector3 &p_point,
                           const godot::Vector3 &p_normal, bool &r_keep1, bool &r_keep2);
    void ApplyAnchorCoupling();
    void UpdateSleepState();
    bool EnvironmentChangedWhileSleeping();

    void SolveFrayConstraints(int p_iter, double p_k_stretch, double p_k_bend, double p_allowed_dev);

    inline void SolvePair(int a, int b, double rest, double k, double *lambda = nullptr);
    inline void SolveBend(int b, int spacing, double allowed_dev, double k);
    inline void SolveBendTriple(int a, int b, int c, double allowed_dev, double k);
    inline void SolveAngleBend(int a, int b, int c, double free_angle, double k);
    inline void SolveBendAnchored(int a, int b, int c, double k);
    inline void SolveMidContact(int s, bool second);
    inline void ProjectPlane(int i, const godot::Vector3 &cp, const godot::Vector3 &n,
                             double &lambda);
    void PinAnchors();
    inline void ResolveContact(int i, const godot::Vector3 &contact, const godot::Vector3 &normal);
    uint64_t BendLambdaKey(int a, int b, int c, bool anchored,
                           double allowed_dev, double strength) const;
    double StubWeight(double base, int k, int n) const;
    bool PlaneValid(int i, const godot::Vector3 &cp, const godot::Vector3 &n) const;

    // ── Anchors ──────────────────────────────────────────────────────────────
    godot::Vector3 AnchorPoint(godot::Node3D *node, const godot::Vector3 &offset,
                               const godot::Vector3 &fallback) const;
    bool AnchorsMoved() const;
    bool AnchorTeleported() const;
    EndpointRole ResolveEndpointRole(godot::Node3D *node, int configured_role) const;
    static bool EndpointIsFixed(EndpointRole role);
    static bool EndpointIsDirectional(EndpointRole role);
    static bool EndpointIsFree(EndpointRole role);
    bool PlugIsFixed(godot::Node3D *node) const;
    godot::Vector3 PlugExitDir(godot::Node3D *node, const godot::Vector3 &axis) const;
    // Pin reactions: slot 0 is the trunk's start, 1 its end, 2+g fray chain g.
    int PinSlot(int p_particle) const;
    inline void AddPinReaction(int p_pinned, const godot::Vector3 &p_push,
                               const godot::Vector3 &p_arm);
    bool PlugIsCoupled(godot::Node3D *node, int p_configured_role) const;
    void CouplePlug(godot::Node3D *node, int p_configured_role, const godot::Vector3 &offset,
                    int p_slot, double p_segment_length);
    void RefreshExclusions();
    void DepenetrateLay();
    // Resolved once per tick so the hot paths don't repeat the ObjectDB lookup.
    void CacheAnchors();
    bool ReconcileAnchors();

    // ── Ribbon ───────────────────────────────────────────────────────────────
    // Lateral pitch between neighbouring cords. Zero means "touching".
    double CordPitch() const { return m_ribbon_spacing > 0.0 ? m_ribbon_spacing : m_tube_radius * 2.0; }
    double FraySegLength() const
    {
        return m_fray_segment_length > 0.0 ? m_fray_segment_length : m_segment_length;
    }
    int TrunkCount() const { return m_segment_count + 1; }
    void BuildFrayChains(int &r_total);
    // Rewrite the rest distances in place, without disturbing the layout.
    void RefreshSegmentRest();
    // Gathers cord c's whole drawn centreline — its start branch reversed, then
    // the trunk, then its end branch — into m_cord_points, with the lateral
    // offset it sits at each point (in cord pitches) into m_cord_lat.
    void BuildCordPath(int p_cord);
    int CordPointCount() const;
    void RebuildMaterials();
    godot::Color CordColor(int p_cord) const;

    // ── Rendering ────────────────────────────────────────────────────────────
    void BuildTrigTables();
    void BuildMeshTopology();
    void FillRingPoints(const std::vector<godot::Vector3> &p_src, bool p_with_lat);
    // True for a plain single round cord — the shape every cable in the project
    // still is. Skips the ribbon gather entirely so they mesh at the old cost.
    bool IsPlainCord() const { return m_fray.empty() && m_built_cords <= 1; }
    void RenderTube();
    bool RibbonEndsTurned() const;
    void RenderCord(int p_cord);
    void SnapshotRenderState();
    int Subdiv() const { return m_smoothing + 1; }
    void SleepNow();
    void OpenExcursionWindow();

    // ── State ────────────────────────────────────────────────────────────────
    std::vector<godot::Vector3> m_points;
    std::vector<godot::Vector3> m_prev_points;
    std::vector<float> m_inv_mass;
    // Hands on the cord (see HoldPoint). A handful at most.
    struct Hold
    {
        int index = -1;
        godot::Vector3 target;
        // Where the particle was when the tick began, and what it moved a
        // slice of the last tick: the velocity it is let go with.
        godot::Vector3 from;
        godot::Vector3 slice_velocity;
        float free_inv_mass = 1.0f;
    };
    std::vector<Hold> m_holds;

    std::vector<uint8_t> m_mid_contact;
    std::vector<godot::Vector3> m_mid_contact_point;
    std::vector<godot::Vector3> m_mid_contact_normal;
    std::vector<float> m_mid_contact_t;
    std::vector<godot::Vector3> m_mid_contact_point_2;
    std::vector<godot::Vector3> m_mid_contact_normal_2;
    std::vector<float> m_mid_contact_t_2;
    // A segment lying over a sharp EDGE (m_mid_contact bit 4, with bit 1): the
    // edge's line and the two faces that meet in it. Slot 1 of the segment's
    // contact is then re-derived from this line every tick, so the contact
    // slides along the segment as the cord is pulled round the corner.
    std::vector<godot::Vector3> m_edge_point;
    std::vector<godot::Vector3> m_edge_dir;
    std::vector<godot::Vector3> m_edge_n1;
    std::vector<godot::Vector3> m_edge_n2;

    std::vector<uint8_t> m_c_flags;
    std::vector<godot::Vector3> m_c_p1;
    std::vector<godot::Vector3> m_c_n1;
    std::vector<godot::Vector3> m_c_p2;
    std::vector<godot::Vector3> m_c_n2;
    std::vector<uint8_t> m_stuck_passes;
    std::vector<uint8_t> m_settle_touching;

    std::vector<int> m_active_mid;
    std::vector<int> m_active_contact;

    // Segment table. With a fray the particle array is no longer one chain, so
    // "segment i joins particle i and i+1" stops being true and everything
    // adjacency-aware indexes through here instead. m_mid_contact* are sized to
    // this, not to segment_count.
    std::vector<int> m_seg_a;
    std::vector<int> m_seg_b;
    // Double, not float. This feeds SolvePair's rest distance, which used to be
    // m_segment_length read straight off the member. Narrowing it shifts the
    // settled pose by ~1e-8 m, which sounds harmless and is not: a cable resting
    // on a table edge sits right at a contact-detection threshold, and nudging
    // it across took the rope_bench settle count from 9 cables still awake
    // to 15.
    std::vector<double> m_seg_rest;
    // XPBD multipliers live for one physics step and accumulate across solver
    // iterations. They are reset before every solve, never persisted in saves.
    std::vector<double> m_stretch_lambda;
    std::vector<double> m_mid_contact_lambda;
    std::vector<double> m_mid_contact_lambda_2;
    std::vector<double> m_contact_lambda_1;
    std::vector<double> m_contact_lambda_2;
    std::unordered_map<uint64_t, godot::Vector3> m_bend_lambda;
    std::unordered_map<uint64_t, double> m_angle_lambda;
    // What the rope did to each pinned end this step, as the displacement the
    // pin would have taken had it been free (summed over every iteration), and
    // that displacement's moment about the pin. Indexed by PinSlot.
    std::vector<godot::Vector3> m_pin_push;
    std::vector<godot::Vector3> m_pin_moment;
    // Friction scratch, per particle: its summed contact load this step and the
    // plane bearing hardest on it.
    std::vector<double> m_fric_load;
    std::vector<double> m_fric_heaviest;
    std::vector<godot::Vector3> m_fric_normal;
    std::vector<int> m_fric_touched;
    // One place the cord touches itself this tick: a point on segment (a0, a1)
    // at `s` against a point on segment (b0, b1) at `t`. Two particles are the
    // same thing with a0 == a1 and b0 == b1.
    struct SelfContact
    {
        int a0, a1, b0, b1;
        float s, t;
        // Inverse masses, zeroed for an end the push would drive into the
        // surface it rests on.
        float wa0, wa1, wb0, wb1;
        // Closest the two may come.
        double clearance;
        // From a to b when found, for the tick they are exactly coincident.
        godot::Vector3 normal;
        // Their approach along the normal before the solve (negative: closing),
        // and how far the solve had to part them, summed over the iterations.
        double closing_before;
        double pushed;
        // Found deep inside each other: parted along `normal` and nothing else.
        bool fixed;
    };
    std::vector<SelfContact> m_self_contacts;
    std::vector<godot::Vector3> m_self_mid;
    std::vector<float> m_self_half;
    // How far the self contacts moved each particle this step, summed over
    // the iterations: that much of its move is not velocity.
    std::vector<godot::Vector3> m_self_moved;
    double m_step_dt_sq = 1.0 / (60.0 * 60.0);
    // Substepping: where every particle was when the tick began (the sweeps
    // cover the whole tick's motion, not the last slice's), where each pinned
    // end was, and how far through the tick the pins have been carried.
    std::vector<godot::Vector3> m_tick_from;
    std::vector<godot::Vector3> m_pin_from;
    // Where each pinned end is going this tick, read once in StepBegin.
    std::vector<godot::Vector3> m_pin_target;
    bool m_pins_cached = false;
    // What StepBegin decided for StepSolve.
    int m_step_substeps = 1;
    double m_step_slice = 0.0;
    bool m_step_start_directional = false;
    bool m_step_end_directional = false;
    godot::Vector3 m_step_start_exit;
    godot::Vector3 m_step_end_exit;
    // The physics frame this cord's solve was batched on, and whether its
    // StepEnd is still owed.
    uint64_t m_batched_frame = UINT64_MAX;
    bool m_solve_pending = false;
    std::vector<godot::Vector3> m_pin_velocity;
    double m_pin_fraction = 1.0;
    int m_iterations_now = 0;
    // Segment starting at each particle, or -1 — only used to invalidate a
    // midpoint cache after the tunnel recovery moves a particle.
    std::vector<int> m_next_seg;
    // Segment ending at each particle, or -1.
    std::vector<int> m_prev_seg;
    // 0 collides normally; two particles sharing a non-zero id are coincident by
    // construction (a junction) and skip each other. Two ids, not a flag: a
    // particle at the start junction must still collide with one at the end.
    std::vector<uint8_t> m_self_group;

    std::vector<FrayChain> m_fray;
    // Per cord: which fray chain it follows at each end (-1 for none), the
    // lateral slot it sits in along the trunk, and the slot it eases to inside
    // its group. All in cord pitches, signed about the ribbon's centre.
    std::vector<int> m_cord_start_chain;
    std::vector<int> m_cord_end_chain;
    std::vector<float> m_lat_trunk;
    std::vector<float> m_lat_start;
    std::vector<float> m_lat_end;
    // Fray anchors keyed by group index, kept apart from m_fray because
    // GDScript sets them before _init_points has worked out the groups.
    std::vector<uint64_t> m_fray_start_ids;
    std::vector<uint64_t> m_fray_end_ids;
    std::vector<godot::Vector3> m_fray_start_offsets;
    std::vector<godot::Vector3> m_fray_end_offsets;

    std::vector<godot::Vector3> m_render_points;
    std::vector<godot::Vector3> m_prev_render;
    std::vector<godot::Vector3> m_curr_render;

    std::vector<float> m_cos_table;
    std::vector<float> m_sin_table;
    std::vector<godot::Vector3> m_ring_points;
    std::vector<godot::Vector3> m_ring_side;
    std::vector<godot::Vector3> m_ring_up;
    std::vector<float> m_ring_lat;
    // One cord's gathered centreline and lateral track, before subdivision.
    std::vector<godot::Vector3> m_cord_points;
    std::vector<float> m_cord_lat;

    // Vertex/attribute staging buffers, one per cord, reused every frame — the
    // region upload wants bytes, so the sim writes straight into these.
    std::vector<godot::PackedByteArray> m_vertex_bytes;
    std::vector<godot::PackedByteArray> m_normal_bytes;

    std::vector<godot::Ref<godot::ShaderMaterial>> m_materials;
    godot::Ref<godot::PhysicsRayQueryParameters3D> m_ray_query;
    godot::Ref<godot::PhysicsShapeQueryParameters3D> m_shape_query;
    godot::Ref<godot::PhysicsShapeQueryParameters3D> m_segment_shape_query;
    godot::Ref<godot::PhysicsPointQueryParameters3D> m_point_query;
    godot::Ref<godot::SphereShape3D> m_sphere;
    godot::Ref<godot::CapsuleShape3D> m_segment_capsule;

    uint64_t m_start_node_id = 0;
    uint64_t m_end_node_id = 0;
    godot::Node3D *m_start_cached = nullptr;
    godot::Node3D *m_end_cached = nullptr;
    godot::RigidBody3D *m_start_body = nullptr;
    godot::RigidBody3D *m_end_body = nullptr;

    int m_raycast_frame = 0;
    int m_sleep_environment_frame = 0;
    int m_sleep_poll_phase = 0;
    int m_environment_change_polls = 0;
    // Set by InitPoints, consumed by the first Step after a lay: run
    // DepenetrateLay there, where space-state queries are legal.
    bool m_depen_pending = false;
    // A particle went non-finite: logged once a cord, re-laid every time (StepBegin).
    bool m_nonfinite_logged = false;
    // Ticks both ends have been still, whatever the cord itself is doing (UpdateSleepState's forced sleep).
    int m_ends_still_frames = 0;
    bool m_forced_sleep_logged = false;
    bool m_settle_repair_attempted = false;
    // Not reset by InitPoints, on purpose: only an end moving allows another.
    int m_hopeless_frames = 0;
    bool m_relay_attempted = false;
    bool m_asleep = false;
    int m_still_frames = 0;
    int m_contact_stable_frames = 0;
    godot::Vector3 m_sleep_anchor_start;
    godot::Vector3 m_sleep_anchor_end;
    bool m_mesh_dirty = true;
    // Where each connector's ribbon lay pointed when the mesh was last built.
    godot::Vector3 m_meshed_start_lay;
    godot::Vector3 m_meshed_end_lay;
    bool m_interpolating = false;
    double m_debug_max_velocity = 0.0;
    double m_debug_rms_velocity = 0.0;
    double m_debug_stretch_error = 0.0;
    double m_debug_contact_error = 0.0;
    // Running totals of the discrete things collision did, for probes that ask
    // WHICH pass kicked a cord (get_sleep_metrics): a particle's swept snap, a
    // segment contact whose plane turned to another face, a swept capsule stop,
    // a wrong-side teleport, and self-collision's particle and segment pairs.
    int m_debug_sweep_snaps = 0;
    int m_debug_mid_turns = 0;
    int m_debug_capsule_stops = 0;
    int m_debug_recoveries = 0;
    int m_debug_self_pairs = 0;
    int m_debug_self_segments = 0;
    int m_debug_edges_found = 0;
    int m_debug_edge_handovers = 0;
    int m_debug_edges_lost = 0;
    // KeepTautOutside: the cord ended its last tick with every segment clear.
    bool m_taut_clear = false;
    // Segments holding a face KeepTautOutside gave them (m_mid_contact bit 8).
    int m_taut_holds = 0;
    // Segments found through something, being walked round it (FindCrossings).
    struct Escape
    {
        int segment = -1;
        godot::Vector3 target;
        int ticks = 0;
        // Which of its ends this pinned for the walk (HoldPoint).
        bool pin_a = false;
        bool pin_b = false;
    };
    std::vector<Escape> m_escapes;
    void DropEscapes();
    // Look for them at the next tick's end: set by a wake and by a lay.
    bool m_cross_check = false;
    bool m_escape_logged = false;
    int m_debug_escapes = 0;
    int m_debug_taut_crossings = 0;
    int m_debug_taut_edges = 0;
    int m_debug_taut_rollbacks = 0;
    int m_debug_taut_whole = 0;
    // XENU_ROPE_DIAG: one second's worth of why this cord is awake.
    int m_diag_ticks = 0;
    int m_diag_not_still = 0;
    int m_diag_anchor_moved = 0;
    int m_diag_unsettled = 0;
    int m_diag_wake_anchor = 0;
    int m_diag_wake_env = 0;
    int m_diag_wake_call = 0;
    double m_diag_peak = 0.0;
    // Cord count and ring count the current ArrayMesh was built for, so a
    // resize after _ready rebuilds instead of overrunning the ring buffers.
    int m_built_cords = 0;
    int m_built_rings = 0;
    // Cords of one colour share a single surface; see BuildMeshTopology.
    bool m_built_merged = false;
    int m_built_vertices = 0;
    bool CordsShareColour() const;
    int m_built_sides = 0;

    // ── Exported values ──────────────────────────────────────────────────────
    int m_segment_count = 15;
    double m_segment_length = 0.06;
    godot::Vector3 m_gravity = godot::Vector3(0, -9.8, 0);
    double m_damping = 0.01;
    int m_constraint_iterations = 5;
    double m_stretch_stiffness = 1.0;
    double m_bend_stiffness = 0.0;
    // Physical compliance (inverse stiffness), divided by dt^2 by XPBD. Zero
    // deliberately selects the legacy stiffness path for scene compatibility.
    double m_stretch_compliance = 0.0;
    double m_bend_compliance = 0.0;
    double m_contact_compliance = 0.000001;
    double m_max_bend_degrees = 0.0;
    // Above this local turn, bend_stiffness ramps progressively. The limit is
    // the adjacent-segment case self-collision cannot handle because neighbours
    // share a particle and are deliberately excluded from each other.
    double m_bend_stiffen_degrees = 150.0;
    double m_bend_limit_degrees = 175.0;
    double m_tube_radius = 0.005;
    int m_tube_sides = 8;
    int m_smoothing = 0;
    godot::Color m_rope_color = godot::Color(0.15f, 0.15f, 0.15f, 1.0f);
    int m_surface_collision_mask = 7;
    double m_collision_radius = 0.008;
    // Viscous slide damping, applied only when both Coulomb coefficients are
    // zero (and to the swept landing, which has no load to measure).
    double m_surface_friction = 0.4;
    // Coulomb friction against every surface the cord rests on: a point that
    // slid less than static_friction x the surface's push this step is put back
    // (it sticks), otherwise its slide is cut by kinetic_friction x the push.
    // A PVC jacket on wood or carpet.
    double m_static_friction = 0.7;
    double m_kinetic_friction = 0.5;
    // Cord mass per metre, kg. Turns the solver's corrections against a loose
    // plug into newtons. A composite A/V lead is 30-50 g/m.
    double m_linear_density = 0.04;
    int m_raycast_interval = 3;
    // PROTOTYPE. The solve is run this many times a tick, each over a slice of
    // the tick with its share of the iterations; the environment is still
    // queried once a tick. 1 is the solver as it always was.
    int m_substeps = 4;
    // Probe control legs only, never saved: 1 no edge contacts, 2 no strand
    // friction, 4 no rays confirming a cached plane.
    int m_debug_disable = 0;
    double m_wave_damping = 0.3;
    std::vector<godot::Vector3> m_velocity_scratch;
    bool m_self_collision = false;
    double m_anchor_pull = 0.0;
    // Name kept for the scenes that set it: any value above zero couples a
    // loose RigidBody plug to the cord (the cord leaves along its exit axis and
    // pushes back on it through forces). Zero leaves the plug untouched.
    double m_end_align_stiffness = 0.0;
    godot::Vector3 m_start_exit_axis = godot::Vector3(0, 0, -1);
    godot::Vector3 m_end_exit_axis = godot::Vector3(0, 0, -1);
    int m_start_endpoint_role = ENDPOINT_AUTO;
    int m_end_endpoint_role = ENDPOINT_AUTO;
    godot::Vector3 m_start_anchor_offset;
    godot::Vector3 m_end_anchor_offset;
    double m_end_stiffness = 0.0;
    int m_end_stiff_segments = 3;

    // Ribbon. The defaults are a single round cord, so every existing cable
    // behaves exactly as it did before any of this existed.
    int m_ribbon_count = 1;
    double m_ribbon_spacing = 0.0;
    godot::PackedColorArray m_ribbon_colors;
    godot::Vector3 m_ribbon_axis = godot::Vector3(1, 0, 0);
    int m_fray_segments_start = 0;
    int m_fray_segments_end = 0;
    double m_fray_segment_length = 0.0;
    // Over how many branch particles a cord slides from its trunk slot to its
    // in-group slot. 2 completes half the move in one segment, which kinks the
    // tube visibly where a cord has to cross the ribbon; 3 is the shortest that
    // reads as a moulded breakout rather than a snag.
    int m_fray_taper_segments = 3;
    godot::PackedInt32Array m_fray_start_groups;
    godot::PackedInt32Array m_fray_end_groups;
};

} // namespace Xenu

VARIANT_ENUM_CAST(Xenu::VerletRope::EndpointRole);
