#pragma once

// GbPaperContacts, ported: a 4 cm grid over the finite surface patches round a
// piece of paper. Bounds only throw out contacts that cannot happen; the
// solvers still test each candidate exactly, in the patches' own order. Large
// recovery patches go on an unbinned list.

#include "PaperMath.hpp"

#include <algorithm>
#include <cstdint>
#include <unordered_map>
#include <vector>

namespace Xenu::Paper
{
// [normal, offset, center, reach, depth] in the strip's (Y, Z).
struct Patch2
{
    Vector2 normal;
    double offset = 0.0;
    Vector2 center;
    double reach = 0.0;
    double depth = 0.0;
};

// The same in the ribbon's body frame.
struct Patch3
{
    Vector3 normal;
    double offset = 0.0;
    Vector3 center;
    double reach = 0.0;
    double depth = 0.0;
};

class Contacts
{
public:
    static constexpr double CELL = 0.04;
    static constexpr int MAX_CELLS = 64;
    static constexpr double PAD = 0.000001;

    void build_2d(const std::vector<Patch2> &patches, double skin)
    {
        clear();
        for (int i = 0; i < (int)patches.size(); i++) {
            const Patch2 &patch = patches[i];
            Vector2 n = patch.normal;
            Vector2 center = patch.center;
            double depth = patch.depth;
            center += n * (real_t)(patch.offset + skin - depth * 0.5 - (double)n.dot(center));
            Vector2 half = Vector2((real_t)std::fabs((double)n.y), (real_t)std::fabs((double)n.x)) * (real_t)patch.reach
                + n.abs() * (real_t)depth * (real_t)0.5;
            AABB bounds(Vector3((real_t)((double)center.x - (double)half.x), (real_t)((double)center.y - (double)half.y), 0),
                Vector3((real_t)((double)half.x * 2), (real_t)((double)half.y * 2), 0));
            insert(i, bounds.grow((real_t)PAD));
        }
    }

    void build_3d(const std::vector<Patch3> &patches, double skin)
    {
        clear();
        for (int i = 0; i < (int)patches.size(); i++) {
            const Patch3 &patch = patches[i];
            Vector3 n = patch.normal;
            Vector3 center = patch.center;
            double depth = patch.depth;
            center += n * (real_t)(patch.offset + skin - depth * 0.5 - (double)n.dot(center));
            Vector3 half = Vector3(
                    (real_t)std::sqrt(gmax(0.0, 1 - (double)n.x * (double)n.x)),
                    (real_t)std::sqrt(gmax(0.0, 1 - (double)n.y * (double)n.y)),
                    (real_t)std::sqrt(gmax(0.0, 1 - (double)n.z * (double)n.z)))
                    * (real_t)patch.reach
                + n.abs() * (real_t)depth * (real_t)0.5;
            insert(i, AABB(center - half, half * (real_t)2).grow((real_t)PAD));
        }
    }

    // The caller moved every patch by -shift (the ribbon's body recovery).
    void shift_frame(const Vector3 &shift) { _shift += shift; }

    // The patches near `p`, in their order.
    const std::vector<int> &query(const Vector3 &p)
    {
        auto it = _cells.find(cell(p + _shift));
        const std::vector<int> &nearby = it == _cells.end() ? _empty : it->second;
        if (_large.empty())
            return nearby;
        _merged = nearby;
        _merged.insert(_merged.end(), _large.begin(), _large.end());
        std::sort(_merged.begin(), _merged.end());
        return _merged;
    }

private:
    struct Key
    {
        int32_t x, y, z;
        bool operator==(const Key &o) const { return x == o.x && y == o.y && z == o.z; }
    };
    struct KeyHash
    {
        size_t operator()(const Key &k) const
        {
            return ((size_t)(uint32_t)k.x * 73856093u) ^ ((size_t)(uint32_t)k.y * 19349663u) ^ ((size_t)(uint32_t)k.z * 83492791u);
        }
    };

    void clear()
    {
        _cells.clear();
        _large.clear();
        _shift = Vector3();
    }

    // floori(p.x / CELL): the component read as a double, as GDScript reads it.
    static Key cell(const Vector3 &p)
    {
        return Key{(int32_t)std::floor((double)p.x / CELL), (int32_t)std::floor((double)p.y / CELL),
            (int32_t)std::floor((double)p.z / CELL)};
    }

    void insert(int index, const AABB &bounds)
    {
        Key lo = cell(bounds.position);
        Key hi = cell(bounds.get_end());
        int64_t sx = (int64_t)hi.x - lo.x + 1, sy = (int64_t)hi.y - lo.y + 1, sz = (int64_t)hi.z - lo.z + 1;
        if (sx * sy * sz > MAX_CELLS) {
            _large.push_back(index);
            return;
        }
        for (int32_t x = lo.x; x <= hi.x; x++)
            for (int32_t y = lo.y; y <= hi.y; y++)
                for (int32_t z = lo.z; z <= hi.z; z++)
                    _cells[Key{x, y, z}].push_back(index);
    }

    std::unordered_map<Key, std::vector<int>, KeyHash> _cells;
    std::vector<int> _large;
    std::vector<int> _merged;
    const std::vector<int> _empty;
    Vector3 _shift;
};
} // namespace Xenu::Paper
