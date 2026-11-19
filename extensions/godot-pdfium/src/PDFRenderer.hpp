#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/vector2.hpp>

#include "fpdfview.h"

namespace Xenu
{
/// Renders PDF pages to Godot Images using the PDFium library.
/// Usage from GDScript:
///   var pdf := PDFRenderer.new()
///   pdf.Open("C:/path/to/manual.pdf")
///   var img := pdf.RenderPage(0, 150)   # page index, DPI
///   var tex := ImageTexture.create_from_image(img)
class PDFRenderer : public godot::RefCounted
{
    GDCLASS(PDFRenderer, godot::RefCounted);

public:
    PDFRenderer();
    ~PDFRenderer();

    /// Open a PDF file at the given absolute path. Returns true on success.
    bool Open(const godot::String& path);

    /// Close the currently open document and free resources.
    void Close();

    /// Returns true if a document is currently open.
    bool IsOpen() const;

    /// Total number of pages in the open document.
    int GetPageCount() const;

    /// Page dimensions in PDF points (1 point = 1/72 inch).
    /// Returns Vector2(width, height) or Vector2.ZERO on error.
    godot::Vector2 GetPageSize(int page_index) const;

    /// Render a single page to an RGBA8 Godot Image at the given DPI.
    /// Returns a valid Image on success, or an empty Ref on failure.
    godot::Ref<godot::Image> RenderPage(int page_index, int dpi = 150) const;

    /// Library-level init/shutdown — call once at module load/unload.
    static void InitLibrary();
    static void DestroyLibrary();

protected:
    static void _bind_methods();

private:
    FPDF_DOCUMENT m_document = nullptr;
    godot::String m_path;
};
}
