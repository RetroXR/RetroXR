// avsync_probe — where the A/V skew on the libVLC path comes from.
//
// Wires libVLC exactly as VlcPlayer does (RGBA vmem video callbacks, S16N
// 48 kHz stereo amem audio callbacks) and records, over a fixed run:
//
//   * the play date libVLC stamps on each PCM block against the clock at the
//     moment the block is handed over — how far ahead of its own deadline the
//     audio arrives
//   * when each picture is handed over, so it can be seen whether the picture
//     side is paced to that same clock or delivered as fast as it decodes
//   * the gap between those two, sampled at each picture
//
// Together they fix the budget. Audio is heard at (arrival + whatever we queue)
// and a picture is seen at (arrival + our render latency), so the skew follows
// from the lead the audio arrived with. VlcPlayer discards that lead —
// cb_audio_play ignores its pts — which is why its queue depth has to be
// guessed rather than derived.
//
// Build (Windows, from the repo root, in a vcvars64 shell):
//   cl /nologo /std:c++20 /EHsc /O2 /I vlc-godot\vendor\include \
//      /Fe:avsync_probe.exe vlc-godot\tools\avsync_probe.cpp \
//      vlc-godot\vendor\lib\libvlc.lib
//
// Run from beside libvlc.dll and the plugin tree:
//   cd RetroXR\vlc-godot
//   avsync_probe.exe C:/Users/me/retroxr/dvd/SHREK.ISO dvd 20

#include <vlc/vlc.h>

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace
{

constexpr int kRate = 48000;
constexpr int kChannels = 2;

struct AudioEvent
{
    int64_t arrived;   ///< libvlc_clock() on entry to the play callback
    int64_t pts;       ///< play date libVLC stamped on the block
    unsigned frames;
};

struct VideoEvent
{
    int64_t arrived;      ///< libvlc_clock() on entry to the display callback
    int64_t audio_pts;    ///< pts of the most recent PCM block at that moment
    int64_t audio_lead;   ///< that block's lead when it arrived
};

struct Probe
{
    std::mutex mutex;
    std::vector<uint8_t> decode;
    unsigned width = 0;
    unsigned height = 0;

    std::vector<AudioEvent> audio;
    std::vector<VideoEvent> video;

    int64_t last_audio_pts = 0;
    int64_t last_audio_lead = 0;

    int64_t started = 0;
};

// ── video callbacks (identical shape to VlcPlayer's) ────────────────────────

unsigned cb_format(void **opaque, char *chroma, unsigned *width, unsigned *height,
                   unsigned *pitches, unsigned *lines)
{
    Probe *p = static_cast<Probe *>(*opaque);
    std::memcpy(chroma, "RGBA", 4);
    *pitches = *width * 4;
    *lines = *height;
    std::lock_guard<std::mutex> lock(p->mutex);
    p->width = *width;
    p->height = *height;
    p->decode.assign((size_t)*width * *height * 4, 0);
    return 1;
}

void cb_cleanup(void *opaque)
{
    Probe *p = static_cast<Probe *>(opaque);
    std::lock_guard<std::mutex> lock(p->mutex);
    p->decode.clear();
}

void *cb_lock(void *opaque, void **planes)
{
    Probe *p = static_cast<Probe *>(opaque);
    planes[0] = p->decode.empty() ? nullptr : p->decode.data();
    return nullptr;
}

void cb_unlock(void *, void *, void *const *) {}

void cb_display(void *opaque, void *)
{
    Probe *p = static_cast<Probe *>(opaque);
    const int64_t now = libvlc_clock();
    std::lock_guard<std::mutex> lock(p->mutex);
    p->video.push_back(VideoEvent{ now, p->last_audio_pts, p->last_audio_lead });
}

// ── audio callbacks ─────────────────────────────────────────────────────────

void cb_audio_play(void *data, const void *, unsigned count, int64_t pts)
{
    Probe *p = static_cast<Probe *>(data);
    const int64_t now = libvlc_clock();
    std::lock_guard<std::mutex> lock(p->mutex);
    p->audio.push_back(AudioEvent{ now, pts, count });
    p->last_audio_pts = pts;
    p->last_audio_lead = pts - now;
}

void cb_audio_flush(void *data, int64_t)
{
    Probe *p = static_cast<Probe *>(data);
    std::lock_guard<std::mutex> lock(p->mutex);
    std::printf("  [flush] at %.2f s\n", (libvlc_clock() - p->started) / 1e6);
}

// ── reporting ───────────────────────────────────────────────────────────────

void quantiles(std::vector<int64_t> v, const char *label, const char *unit, double scale)
{
    if (v.empty())
    {
        std::printf("  %-22s (no samples)\n", label);
        return;
    }
    std::sort(v.begin(), v.end());
    auto q = [&](double f) { return v[(size_t)(f * (v.size() - 1))] / scale; };
    double mean = 0.0;
    for (int64_t x : v)
        mean += (double)x;
    mean /= (double)v.size();
    std::printf("  %-22s n=%-6zu min %8.1f  p10 %8.1f  med %8.1f  p90 %8.1f  max %8.1f  mean %8.1f %s\n",
                label, v.size(), q(0.0), q(0.10), q(0.50), q(0.90), q(1.0), mean / scale, unit);
}

} // namespace

int main(int argc, char **argv)
{
    std::setvbuf(stdout, nullptr, _IONBF, 0);
    if (argc < 2)
    {
        std::printf("usage: avsync_probe <path> [dvd|file] [seconds]\n");
        return 1;
    }
    std::string path = argv[1];
    const bool is_dvd = (argc > 2) ? (std::strcmp(argv[2], "dvd") == 0) : true;
    const int seconds = (argc > 3) ? std::atoi(argv[3]) : 20;

    if (!std::getenv("VLC_PLUGIN_PATH"))
    {
#ifdef _WIN32
        _putenv_s("VLC_PLUGIN_PATH", "plugins");
#else
        setenv("VLC_PLUGIN_PATH", "plugins", 1);
#endif
    }

    // Same arguments VlcPlayer passes.
    const char *args[] = { "--no-video-title-show", "--no-snapshot-preview", "--quiet" };
    libvlc_instance_t *vlc = libvlc_new(sizeof(args) / sizeof(args[0]), args);
    if (!vlc)
    {
        std::printf("libvlc_new failed\n");
        return 1;
    }

    for (char &c : path)
        if (c == '\\')
            c = '/';
    if (path.front() != '/')
        path.insert(path.begin(), '/');
    const std::string mrl = (is_dvd ? std::string("dvd://") : std::string("file://")) + path;
    std::printf("mrl: %s\n", mrl.c_str());

    libvlc_media_t *media = libvlc_media_new_location(vlc, mrl.c_str());
    if (!media)
    {
        std::printf("media creation failed: %s\n", libvlc_errmsg() ? libvlc_errmsg() : "?");
        return 1;
    }
    libvlc_media_player_t *mp = libvlc_media_player_new_from_media(media);
    libvlc_media_release(media);
    if (!mp)
    {
        std::printf("player creation failed\n");
        return 1;
    }

    Probe probe;
    probe.started = libvlc_clock();

    libvlc_video_set_callbacks(mp, cb_lock, cb_unlock, cb_display, &probe);
    libvlc_video_set_format_callbacks(mp, cb_format, cb_cleanup);
    libvlc_audio_set_format(mp, "S16N", kRate, kChannels);
    libvlc_audio_set_callbacks(mp, cb_audio_play, nullptr, nullptr, cb_audio_flush, nullptr, &probe);

    libvlc_media_player_play(mp);
    std::printf("running %d s ...\n", seconds);
    std::this_thread::sleep_for(std::chrono::seconds(seconds));

    std::vector<AudioEvent> audio;
    std::vector<VideoEvent> video;
    int64_t started = 0;
    {
        std::lock_guard<std::mutex> lock(probe.mutex);
        audio = probe.audio;
        video = probe.video;
        started = probe.started;
        std::printf("video size: %ux%u\n", probe.width, probe.height);
    }

    libvlc_media_player_stop(mp);
    libvlc_media_player_release(mp);
    libvlc_release(vlc);

    const double elapsed = (double)seconds;
    uint64_t frames = 0;
    for (const AudioEvent &e : audio)
        frames += e.frames;

    std::printf("\n== rates ==\n");
    std::printf("  audio blocks %zu, %llu frames = %.3f x realtime (%.1f frames/block)\n",
                audio.size(), (unsigned long long)frames,
                (double)frames / (kRate * elapsed),
                audio.empty() ? 0.0 : (double)frames / (double)audio.size());
    std::printf("  pictures     %zu = %.2f fps\n", video.size(), video.size() / elapsed);

    std::printf("\n== audio: how early it is handed over (pts - clock at callback entry) ==\n");
    {
        std::vector<int64_t> lead;
        lead.reserve(audio.size());
        for (const AudioEvent &e : audio)
            lead.push_back(e.pts - e.arrived);
        quantiles(lead, "lead", "ms", 1000.0);

        // Is the lead stable, or does it wander over the run?
        if (audio.size() > 20)
        {
            const size_t seg = audio.size() / 5;
            std::printf("  lead by fifth of the run (ms):");
            for (int s = 0; s < 5; ++s)
            {
                double sum = 0.0;
                for (size_t i = s * seg; i < (s + 1) * seg; ++i)
                    sum += (double)(audio[i].pts - audio[i].arrived);
                std::printf(" %7.1f", sum / seg / 1000.0);
            }
            std::printf("\n");
        }
    }

    std::printf("\n== audio: gap between consecutive callbacks (pacing) ==\n");
    {
        std::vector<int64_t> gap;
        for (size_t i = 1; i < audio.size(); ++i)
            gap.push_back(audio[i].arrived - audio[i - 1].arrived);
        quantiles(gap, "inter-arrival", "ms", 1000.0);
    }

    std::printf("\n== video: gap between consecutive pictures (pacing) ==\n");
    {
        std::vector<int64_t> gap;
        for (size_t i = 1; i < video.size(); ++i)
            gap.push_back(video[i].arrived - video[i - 1].arrived);
        quantiles(gap, "inter-arrival", "ms", 1000.0);
    }

    std::printf("\n== the skew that matters ==\n");
    std::printf("   A picture handed over at time T is meant to be on screen at ~T.\n");
    std::printf("   The audio that belongs with it has a play date of ~T too. So the\n");
    std::printf("   most recent block's play date minus T is how far ahead of the\n");
    std::printf("   picture the audio stream is running when it reaches us.\n");
    {
        std::vector<int64_t> skew;
        for (const VideoEvent &e : video)
            if (e.audio_pts != 0)
                skew.push_back(e.audio_pts - e.arrived);
        quantiles(skew, "audio pts - display", "ms", 1000.0);
    }

    std::printf("\n== first second, blow by blow ==\n");
    for (size_t i = 0; i < audio.size() && i < 12; ++i)
        std::printf("  audio %2zu  t=%7.1f ms  pts=%8.1f ms  lead=%7.1f ms  frames=%u\n", i,
                    (audio[i].arrived - started) / 1000.0, (audio[i].pts - started) / 1000.0,
                    (audio[i].pts - audio[i].arrived) / 1000.0, audio[i].frames);
    for (size_t i = 0; i < video.size() && i < 6; ++i)
        std::printf("  pic   %2zu  t=%7.1f ms\n", i, (video[i].arrived - started) / 1000.0);

    return 0;
}
