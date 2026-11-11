# Build environment for the TieSheet AppImage: Debian 12 (glibc 2.36), so the result runs on
# Debian 12 / Ubuntu 22.04 and anything newer.  fpc 3.2.2 comes from the distribution.
#
# SDL2 and SDL2_ttf are built from the official release sources (the same versions as the
# Windows DLLs) instead of using Debian's packages: Debian's SDL2 links ALSA, PulseAudio,
# libdecor and more directly, so bundling it would drag those along.  Built here, audio is
# off and the X11 / Wayland client libraries are opened with dlopen at run time, so the two
# libraries need nothing but glibc.  SDL2_ttf uses its bundled FreeType and no HarfBuzz
# (a character-cell program never needs text shaping), which keeps libstdc++ out of it too.
FROM debian:12

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
         fpc binutils build-essential pkg-config curl ca-certificates file \
         libx11-dev libxext-dev libxcursor-dev libxi-dev libxfixes-dev libxrandr-dev \
         libxss-dev libxkbcommon-dev libwayland-dev wayland-protocols libdecor-0-dev \
         libegl-dev libgl-dev \
    && rm -rf /var/lib/apt/lists/*

ARG SDL_VER=2.32.10
ARG SDL_SHA=5f5993c530f084535c65a6879e9b26ad441169b3e25d789d83287040a9ca5165
ARG TTF_VER=2.24.0
ARG TTF_SHA=0b2bf1e7b6568adbdbc9bb924643f79d9dedafe061fa1ed687d1d9ac4e453bfd
RUN curl -fL -o /tmp/sdl.tgz https://github.com/libsdl-org/SDL/releases/download/release-${SDL_VER}/SDL2-${SDL_VER}.tar.gz \
    && echo "$SDL_SHA  /tmp/sdl.tgz" | sha256sum -c - \
    && tar -C /tmp -xzf /tmp/sdl.tgz && cd /tmp/SDL2-${SDL_VER} \
    && ./configure --prefix=/opt/sdl --disable-static --disable-audio --disable-joystick \
         --disable-haptic --disable-sensor --disable-hidapi --disable-power --disable-libudev \
         --disable-dbus --disable-ime --disable-ibus --disable-fcitx --disable-video-kmsdrm \
    && make -j"$(nproc)" && make install \
    && rm -rf /tmp/sdl.tgz /tmp/SDL2-${SDL_VER}
RUN curl -fL -o /tmp/ttf.tgz https://github.com/libsdl-org/SDL_ttf/releases/download/release-${TTF_VER}/SDL2_ttf-${TTF_VER}.tar.gz \
    && echo "$TTF_SHA  /tmp/ttf.tgz" | sha256sum -c - \
    && tar -C /tmp -xzf /tmp/ttf.tgz && cd /tmp/SDL2_ttf-${TTF_VER} \
    && PKG_CONFIG_PATH=/opt/sdl/lib/pkgconfig ./configure --prefix=/opt/sdl --with-sdl-prefix=/opt/sdl \
         --disable-static --disable-harfbuzz \
    && make -j"$(nproc)" && make install \
    && rm -rf /tmp/ttf.tgz /tmp/SDL2_ttf-${TTF_VER}

# appimagetool 1.9.1 (static ELF, so no FUSE is needed to package), checked against the
# digest GitHub publishes for that release asset
ARG APPIMAGETOOL_SHA=ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0
RUN curl -fL -o /usr/local/bin/appimagetool \
      https://github.com/AppImage/appimagetool/releases/download/1.9.1/appimagetool-x86_64.AppImage \
    && echo "$APPIMAGETOOL_SHA  /usr/local/bin/appimagetool" | sha256sum -c - \
    && chmod +x /usr/local/bin/appimagetool

# appimagetool is itself an AppImage and a container has no FUSE: self-extract and run
ENV APPIMAGE_EXTRACT_AND_RUN=1

WORKDIR /src
ENTRYPOINT ["packaging/appimage/build.sh"]
