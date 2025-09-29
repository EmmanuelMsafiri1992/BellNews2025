#!/bin/bash
# Emergency Pygame Installation for NanoPi
# Run this script on your NanoPi to fix pygame

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}🚨 Emergency Pygame Installation for NanoPi${NC}"
echo "============================================"

# Find Python command
if command -v python3.10 &>/dev/null; then
    PYTHON_CMD="python3.10"
elif command -v python3 &>/dev/null; then
    PYTHON_CMD="python3"
else
    echo -e "${RED}❌ No Python found!${NC}"
    exit 1
fi

echo -e "${GREEN}Using Python: $PYTHON_CMD${NC}"
$PYTHON_CMD --version

# Method 1: Try building pygame with minimal dependencies
echo -e "${YELLOW}Method 1: Installing pygame with minimal dependencies...${NC}"
export SDL_VIDEODRIVER=dummy
export SDL_AUDIODRIVER=alsa

# Install minimal SDL dependencies
apt-get update -qq
apt-get install -y libsdl1.2-dev libsdl-mixer1.2-dev libsdl-image1.2-dev libsdl-ttf2.0-dev -qq

if $PYTHON_CMD -m pip install pygame --no-cache-dir --no-binary :all: --install-option="--enable-sdlmixer" 2>/dev/null; then
    if $PYTHON_CMD -c "import pygame; pygame.mixer.init(); print('✅ Pygame Method 1 SUCCESS')"; then
        echo -e "${GREEN}✅ Pygame installed successfully with Method 1${NC}"
        exit 0
    fi
fi

# Method 2: Try older pygame version
echo -e "${YELLOW}Method 2: Installing older pygame version...${NC}"
$PYTHON_CMD -m pip uninstall -y pygame 2>/dev/null || true

if $PYTHON_CMD -m pip install pygame==2.0.1 --no-cache-dir 2>/dev/null; then
    if $PYTHON_CMD -c "import pygame; pygame.mixer.init(); print('✅ Pygame Method 2 SUCCESS')"; then
        echo -e "${GREEN}✅ Pygame 2.0.1 installed successfully${NC}"
        exit 0
    fi
fi

# Method 3: Install from Ubuntu repository
echo -e "${YELLOW}Method 3: Installing from system repository...${NC}"
$PYTHON_CMD -m pip uninstall -y pygame 2>/dev/null || true

if apt-get install -y python3-pygame -qq 2>/dev/null; then
    if $PYTHON_CMD -c "import pygame; pygame.mixer.init(); print('✅ Pygame Method 3 SUCCESS')"; then
        echo -e "${GREEN}✅ System pygame installed successfully${NC}"
        exit 0
    fi
fi

# Method 4: Manual build with custom config
echo -e "${YELLOW}Method 4: Custom pygame build...${NC}"
cd /tmp
rm -rf pygame-build
mkdir pygame-build
cd pygame-build

# Download pygame 2.1.2 source
if wget -q https://github.com/pygame/pygame/archive/refs/tags/2.1.2.tar.gz -O pygame.tar.gz; then
    tar -xzf pygame.tar.gz
    cd pygame-2.1.2

    # Create minimal config
    cat > buildconfig/config_unix.py << 'EOF'
SDL = 1
FONT = 1
IMAGE = 1
MIXER = 1
MUSIC = 1
SCRAP = 0
CAMERA = 0
JOYSTICK = 0
EOF

    # Build and install
    export CFLAGS="-march=armv7-a -mfpu=neon-vfpv4"
    if $PYTHON_CMD setup.py build --config && $PYTHON_CMD setup.py install; then
        if $PYTHON_CMD -c "import pygame; pygame.mixer.init(); print('✅ Pygame Method 4 SUCCESS')"; then
            echo -e "${GREEN}✅ Custom pygame build successful${NC}"
            cd /
            rm -rf /tmp/pygame-build
            exit 0
        fi
    fi
fi

# Method 5: Fallback to pygame-ce (Community Edition)
echo -e "${YELLOW}Method 5: Installing pygame Community Edition...${NC}"
$PYTHON_CMD -m pip uninstall -y pygame pygame-ce 2>/dev/null || true

if $PYTHON_CMD -m pip install pygame-ce --no-cache-dir 2>/dev/null; then
    if $PYTHON_CMD -c "import pygame; pygame.mixer.init(); print('✅ Pygame-CE SUCCESS')"; then
        echo -e "${GREEN}✅ Pygame Community Edition installed${NC}"
        exit 0
    fi
fi

# Method 6: Last resort - compile SDL from source
echo -e "${YELLOW}Method 6: Building SDL from source (last resort)...${NC}"
cd /tmp
rm -rf sdl-build
mkdir sdl-build
cd sdl-build

# Install build dependencies
apt-get install -y build-essential cmake libasound2-dev libpulse-dev -qq

# Build minimal SDL
if wget -q https://github.com/libsdl-org/SDL/archive/refs/tags/release-2.0.20.tar.gz -O sdl.tar.gz; then
    tar -xzf sdl.tar.gz
    cd SDL-release-2.0.20

    mkdir build
    cd build
    cmake .. -DCMAKE_BUILD_TYPE=Release -DSDL_STATIC=OFF
    make -j2
    make install
    ldconfig

    cd /tmp
    rm -rf sdl-build

    # Now try pygame again
    export SDL_VIDEODRIVER=dummy
    if $PYTHON_CMD -m pip install pygame --no-cache-dir --force-reinstall 2>/dev/null; then
        if $PYTHON_CMD -c "import pygame; pygame.mixer.init(); print('✅ Pygame Method 6 SUCCESS')"; then
            echo -e "${GREEN}✅ Pygame with custom SDL successful${NC}"
            exit 0
        fi
    fi
fi

echo -e "${RED}❌ All methods failed. Manual intervention required.${NC}"
echo -e "${YELLOW}Debug info:${NC}"
$PYTHON_CMD -c "import sys; print('Python version:', sys.version)"
echo -e "${YELLOW}Try: apt list --installed | grep pygame${NC}"
echo -e "${YELLOW}Try: apt list --installed | grep sdl${NC}"
exit 1