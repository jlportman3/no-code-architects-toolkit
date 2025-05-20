# Base image
FROM python:3.9-slim

# Install system dependencies, build tools, and libraries in a single layer
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    wget \
    tar \
    xz-utils \
    fonts-liberation \
    fontconfig \
    build-essential \
    yasm \
    cmake \
    meson \
    ninja-build \
    nasm \
    libssl-dev \
    libvpx-dev \
    libx264-dev \
    libx265-dev \
    libnuma-dev \
    libmp3lame-dev \
    libopus-dev \
    libvorbis-dev \
    libtheora-dev \
    libspeex-dev \
    libfreetype6-dev \
    libfontconfig1-dev \
    libgnutls28-dev \
    libaom-dev \
    libdav1d-dev \
    librav1e-dev \
    libsvtav1-dev \
    libzimg-dev \
    libwebp-dev \
    git \
    pkg-config \
    autoconf \
    automake \
    libtool \
    libfribidi-dev \
    libharfbuzz-dev \
    && rm -rf /var/lib/apt/lists/*

# Install SRT from source with shallow clone
RUN git clone --depth=1 https://github.com/Haivision/srt.git && \
    cd srt && \
    mkdir build && cd build && \
    cmake -DCMAKE_BUILD_TYPE=Release .. && \
    make -j$(nproc) && \
    make install && \
    cd ../.. && rm -rf srt

# Install SVT-AV1 from source with shallow clone
RUN git clone --depth=1 -b v0.9.0 https://gitlab.com/AOMediaCodec/SVT-AV1.git && \
    cd SVT-AV1/Build && \
    cmake -DCMAKE_BUILD_TYPE=Release .. && \
    make -j$(nproc) && \
    make install && \
    cd ../.. && rm -rf SVT-AV1

# Install libvmaf from source with shallow clone
RUN git clone --depth=1 https://github.com/Netflix/vmaf.git && \
    cd vmaf/libvmaf && \
    meson build --buildtype release && \
    ninja -C build && \
    ninja -C build install && \
    cd ../.. && rm -rf vmaf && \
    ldconfig

# Manually build and install fdk-aac with shallow clone
RUN git clone --depth=1 https://github.com/mstorsjo/fdk-aac && \
    cd fdk-aac && \
    autoreconf -fiv && \
    ./configure --enable-shared && \
    make -j$(nproc) && \
    make install && \
    cd .. && rm -rf fdk-aac && \
    ldconfig

# Install libunibreak with shallow clone
RUN git clone --depth=1 https://github.com/adah1972/libunibreak.git && \
    cd libunibreak && \
    ./autogen.sh && \
    ./configure && \
    make -j$(nproc) && \
    make install && \
    ldconfig && \
    cd .. && rm -rf libunibreak

# Build and install libass with shallow clone
RUN git clone --depth=1 https://github.com/libass/libass.git && \
    cd libass && \
    autoreconf -i && \
    ./configure --enable-libunibreak && \
    make -j$(nproc) && \
    make install && \
    ldconfig && \
    cd .. && rm -rf libass

# Build and install FFmpeg with shallow clone and optimized flags
# Split into smaller steps to better utilize Docker caching
#RUN git clone --depth=1 -b n7.0.2 https://git.ffmpeg.org/ffmpeg.git ffmpeg
# Replace the problematic git clone line with a direct download
# Replace this line:
# RUN git clone --depth=1 -b n7.0.2 https://git.ffmpeg.org/ffmpeg.git ffmpeg
# With these lines:

RUN apt-get update && apt-get install -y wget && \
    wget -O ffmpeg-7.0.2.tar.xz https://ffmpeg.org/releases/ffmpeg-7.0.2.tar.xz && \
    mkdir -p ffmpeg && \
    tar -xf ffmpeg-7.0.2.tar.xz -C ffmpeg --strip-components=1 && \
    rm ffmpeg-7.0.2.tar.xz

WORKDIR /ffmpeg

# Configure FFmpeg with all required options
RUN PKG_CONFIG_PATH="/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/local/lib/pkgconfig" \
    CFLAGS="-I/usr/include/freetype2 -O3" \
    LDFLAGS="-L/usr/lib/x86_64-linux-gnu" \
    ./configure --prefix=/usr/local \
        --enable-gpl \
        --enable-pthreads \
        --enable-neon \
        --enable-libaom \
        --enable-libdav1d \
        --enable-librav1e \
        --enable-libsvtav1 \
        --enable-libvmaf \
        --enable-libzimg \
        --enable-libx264 \
        --enable-libx265 \
        --enable-libvpx \
        --enable-libwebp \
        --enable-libmp3lame \
        --enable-libopus \
        --enable-libvorbis \
        --enable-libtheora \
        --enable-libspeex \
        --enable-libass \
        --enable-libfreetype \
        --enable-libharfbuzz \
        --enable-fontconfig \
        --enable-libsrt \
        --enable-filter=drawtext \
        --extra-cflags="-I/usr/include/freetype2 -I/usr/include/libpng16 -I/usr/include" \
        --extra-ldflags="-L/usr/lib/x86_64-linux-gnu -lfreetype -lfontconfig" \
        --enable-gnutls

# Build FFmpeg (where it was hanging before)
RUN make -j$(nproc)

# Install FFmpeg and clean up
RUN make install && \
    cd .. && \
    rm -rf ffmpeg

WORKDIR /

# Add /usr/local/bin to PATH
ENV PATH="/usr/local/bin:${PATH}"

# Copy fonts into the custom fonts directory
COPY ./fonts /usr/share/fonts/custom

# Rebuild the font cache so that fontconfig can see the custom fonts
RUN fc-cache -f -v

# Set work directory
WORKDIR /app

# Set environment variable for Whisper cache
ENV WHISPER_CACHE_DIR="/app/whisper_cache"

# Create cache directory
RUN mkdir -p ${WHISPER_CACHE_DIR}

# Copy the requirements file first to optimize caching
COPY requirements.txt .

# Install Python dependencies, upgrade pip
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt && \
    pip install openai-whisper && \
    pip install jsonschema

# Create the appuser
RUN useradd -m appuser

# Give appuser ownership of the /app directory
RUN chown appuser:appuser /app

# Switch to the appuser before downloading the model
USER appuser

RUN python -c "import os; print(os.environ.get('WHISPER_CACHE_DIR')); import whisper; whisper.load_model('base')"

# Copy the rest of the application code
COPY . .

# Expose the port the app runs on
EXPOSE 8081

# Set environment variables
ENV PYTHONUNBUFFERED=1

RUN echo '#!/bin/bash\n\
gunicorn --bind 0.0.0.0:8081 \
    --workers ${GUNICORN_WORKERS:-2} \
    --timeout ${GUNICORN_TIMEOUT:-300} \
    --worker-class sync \
    --keep-alive 80 \
    app:app' > /app/run_gunicorn.sh && \
    chmod +x /app/run_gunicorn.sh

# Run the shell script
CMD ["/app/run_gunicorn.sh"]
