## RetroUMD — PSP media.
##
## A UMD is really a small platter sealed inside a square caddy, and this class
## used to build that caddy: a box body, box colliders, a plain moulded-plastic
## material and its own art quad, because none of the disc shader's zone data
## means anything on a box.
##
## It is TEMPORARILY just a disc — the bare 64 mm platter, shaded like every other
## disc. That is why the class survives as an otherwise empty subclass rather than
## being deleted: umd_disc.tscn is what the spawn menu and scene_persistence both
## name for this system, and this is where the caddy goes back when it returns.
##
## What the caddy build needs, when it comes back:
##   * _apply_system_size() to swap DiscMesh for a BoxMesh of
##     MediaDimensions.cart_size("psp") — laid out thin along Y,
##     footprint in XZ, so the snap poses and insert animation keep working — and
##     to override the surface material, since the shader reads a UV2 face class
##     and a lathed radius that a box carries neither of.
##   * _apply_label_art() to put the art on a quad on the caddy's top face, in
##     group "outline_exclude", instead of handing it to the shader.
##   * can_visually_spin() back to false: spinning a sealed caddy spins the shell,
##     and the platter inside is not visible from outside anyway. As a bare disc
##     it is visible, so spinning it is now correct.
class_name RetroUMD
extends RetroDisc
