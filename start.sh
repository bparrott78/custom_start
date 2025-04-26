#!/usr/bin/env bash
set -e
# Use libtcmalloc for better memory management
TCMALLOC="$(ldconfig -p | grep -Po "libtcmalloc.so.\d" | head -n 1)"
export LD_PRELOAD="${TCMALLOC}"

# This is in case there's any special installs or overrides that needs to occur when starting the machine before starting ComfyUI
if [ -f "/workspace/additional_params.sh" ]; then
    chmod +x /workspace/additional_params.sh
    echo "Executing additional_params.sh..."
    /workspace/additional_params.sh
else
    echo "additional_params.sh not found in /workspace. Skipping..."
fi

# Set the network volume path
NETWORK_VOLUME="/workspace"

# Check if NETWORK_VOLUME exists; if not, use root directory instead
if [ ! -d "$NETWORK_VOLUME" ]; then
    echo "NETWORK_VOLUME directory '$NETWORK_VOLUME' does not exist. You are NOT using a network volume. Setting NETWORK_VOLUME to '/' (root directory)."
    NETWORK_VOLUME="/"
    echo "NETWORK_VOLUME directory doesn't exist. Starting JupyterLab on root directory..."
    jupyter-lab --ip=0.0.0.0 --allow-root --no-browser --NotebookApp.token='' --NotebookApp.password='' --ServerApp.allow_origin='*' --ServerApp.allow_credentials=True --notebook-dir=/ &
else
    echo "NETWORK_VOLUME directory exists. Starting JupyterLab..."
    jupyter-lab --ip=0.0.0.0 --allow-root --no-browser --NotebookApp.token='' --NotebookApp.password='' --ServerApp.allow_origin='*' --ServerApp.allow_credentials=True --notebook-dir=/workspace &
fi

COMFYUI_DIR="$NETWORK_VOLUME/ComfyUI"
WORKFLOW_DIR="$NETWORK_VOLUME/ComfyUI/user/default/workflows"

# Set the target directory
CUSTOM_NODES_DIR="$NETWORK_VOLUME/ComfyUI/custom_nodes"

if [ ! -d "$COMFYUI_DIR" ]; then
    mv /ComfyUI "$COMFYUI_DIR"
else
    echo "Directory already exists, skipping move."
fi

if [ -d "$COMFYUI_DIR" ]; then
    echo "ComfyUI directory already exists. Skipping downloads and setup steps."
else
    echo "Downloading CivitAI download script to /usr/local/bin"
    git clone "https://github.com/Hearmeman24/CivitAI_Downloader.git" || { echo "Git clone failed"; exit 1; }
    mv CivitAI_Downloader/download.py "/usr/local/bin/" || { echo "Move failed"; exit 1; }
    chmod +x "/usr/local/bin/download.py" || { echo "Chmod failed"; exit 1; }
    rm -rf CivitAI_Downloader  # Clean up the cloned repo

    if [ -z "$civitai_token" ] || [ "$civitai_token" == "token_here" ]; then
        echo "Error: CivitAI token is not set. Exiting..."
        exit 1
    fi

    echo "Downloading Photon"
    mkdir -p "$NETWORK_VOLUME/ComfyUI/models/checkpoints"
    if [ ! -f "$NETWORK_VOLUME/ComfyUI/models/checkpoints/photon_v1.safetensors" ]; then
        cd "$NETWORK_VOLUME/ComfyUI/models/checkpoints"
        if ! download.py --model 90072; then
            echo "Error: Downloading Photon model failed. Exiting..."
            exit 1
        fi
    fi

    echo "Downloading SDXL Checkpoint"
    mkdir -p "$NETWORK_VOLUME/ComfyUI/models/checkpoints"
    if [ ! -f "$NETWORK_VOLUME/ComfyUI/models/checkpoints/juggernautXL_juggXIByRundiffusion.safetensors" ]; then
        cd "$NETWORK_VOLUME/ComfyUI/models/checkpoints"
        if ! download.py --model 782002; then
            echo "Error: Downloading Juggernaut model failed. Exiting..."
            exit 1
        fi
    fi

    echo "Downloading VAE"
    mkdir -p "$NETWORK_VOLUME/ComfyUI/models/vae"
    if [ ! -f "$NETWORK_VOLUME/ComfyUI/models/vae/sdxl_vae_fp16_fix.safetensors" ]; then
        wget -O "$NETWORK_VOLUME/ComfyUI/models/vae/sdxl_vae_fp16_fix.safetensors" \
        https://huggingface.co/madebyollin/sdxl-vae-fp16-fix/resolve/main/sdxl.vae.safetensors
    fi

    echo "Downloading IC-LIGHT"
    mkdir -p "$NETWORK_VOLUME/ComfyUI/models/diffusion_models/IC-Light"
    if [ ! -f "$NETWORK_VOLUME/ComfyUI/models/diffusion_models/IC-Light/iclight_sd15_fbc.safetensors" ]; then
        wget -O "$NETWORK_VOLUME/ComfyUI/models/diffusion_models/IC-Light/iclight_sd15_fbc.safetensors" \
        https://huggingface.co/lllyasviel/ic-light/resolve/main/iclight_sd15_fbc.safetensors
    fi

    echo "Finished downloading SD1.5 & SDXL models!"

    echo "Downloading additional models"
    mkdir -p "$NETWORK_VOLUME/ComfyUI/models/upscale_models"
    if [ ! -f "$NETWORK_VOLUME/ComfyUI/models/upscale_models/4x-ClearRealityV1.pth" ]; then
        wget -O "$NETWORK_VOLUME/ComfyUI/models/upscale_models/4x-ClearRealityV1.pth" \
        https://huggingface.co/skbhadra/ClearRealityV1/resolve/main/4x-ClearRealityV1.pth
    fi

    mkdir -p "$NETWORK_VOLUME/ComfyUI/models/ultralytics/bbox"
    if [ ! -f "$NETWORK_VOLUME/ComfyUI/models/ultralytics/bbox/face_yolov8m.pt" ]; then
        wget -O "$NETWORK_VOLUME/ComfyUI/models/ultralytics/bbox/face_yolov8m.pt" \
        https://huggingface.co/Bingsu/adetailer/resolve/main/face_yolov8m.pt
    fi

    if [ "$flux_version" == "true" ]; then
        echo "Downloading Flux Dev"
        mkdir -p "$NETWORK_VOLUME/ComfyUI/models/checkpoints"
        if [ ! -f "$NETWORK_VOLUME/ComfyUI/models/checkpoints/flux1-dev-fp8.safetensors" ]; then
            wget -O "$NETWORK_VOLUME/ComfyUI/models/checkpoints/flux1-dev-fp8.safetensors" \
            https://huggingface.co/lllyasviel/flux1_dev/resolve/main/flux1-dev-fp8.safetensors
        fi
        mkdir -p "$NETWORK_VOLUME/ComfyUI/models/controlnet/FLUX.1/InstantX-FLUX1-Dev-Union"
        if [ ! -f "$NETWORK_VOLUME/ComfyUI/models/controlnet/FLUX.1/InstantX-FLUX1-Dev-Union/diffusion_pytorch_model.safetensors" ]; then
            wget -O "$NETWORK_VOLUME/ComfyUI/models/controlnet/FLUX.1/InstantX-FLUX1-Dev-Union/diffusion_pytorch_model.safetensors" \
            https://huggingface.co/InstantX/FLUX.1-dev-Controlnet-Union/resolve/main/diffusion_pytorch_model.safetensors
        fi
    fi

    if [ "$sdxl_version" == "true" ]; then
        IPADAPTER_DIR="$NETWORK_VOLUME/ComfyUI/models/ipadapter"
        CLIPVISION_DIR="$NETWORK_VOLUME/ComfyUI/models/clip_vision"

        mkdir -p "$IPADAPTER_DIR"
        mkdir -p "$CLIPVISION_DIR"

        declare -A IPADAPTER_FILES=(
            ["ip-adapter-plus-face_sdxl_vit-h.safetensors"]="https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/ip-adapter-plus-face_sdxl_vit-h.safetensors"
            ["ip-adapter-plus_sdxl_vit-h.safetensors"]="https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/ip-adapter-plus_sdxl_vit-h.safetensors"
            ["ip-adapter_sdxl_vit-h.safetensors"]="https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/ip-adapter_sdxl_vit-h.safetensors"
            ["ip-adapter-plus-face_sd15.bin"]="https://huggingface.co/h94/IP-Adapter/resolve/main/models/ip-adapter-plus-face_sd15.bin"
            ["ip-adapter-plus-face_sd15.safetensors"]="https://huggingface.co/h94/IP-Adapter/resolve/main/models/ip-adapter-plus-face_sd15.safetensors"
        )

        declare -A CLIPVISION_FILES=(
            ["CLIP-ViT-H-14-laion2B-s32B-b79K.safetensors"]="https://huggingface.co/h94/IP-Adapter/resolve/main/models/image_encoder/model.safetensors"
            ["CLIP-ViT-bigG-14-laion2B-39B-b160k.safetensors"]="https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/image_encoder/model.safetensors"
        )

        download_files "$IPADAPTER_DIR" IPADAPTER_FILES
        download_files "$CLIPVISION_DIR" CLIPVISION_FILES
        mkdir -p "$NETWORK_VOLUME/ComfyUI/models/controlnet/SDXL/controlnet-union-sdxl-1.0"
        if [ ! -f "$NETWORK_VOLUME/ComfyUI/models/controlnet/SDXL/controlnet-union-sdxl-1.0/diffusion_pytorch_model_promax.safetensors" ]; then
            wget -O "$NETWORK_VOLUME/ComfyUI/models/controlnet/SDXL/controlnet-union-sdxl-1.0/diffusion_pytorch_model_promax.safetensors" \
            https://huggingface.co/xinsir/controlnet-union-sdxl-1.0/resolve/main/diffusion_pytorch_model_promax.safetensors
        fi
    fi
fi

cd /

echo "Checking and copying workflow..."
mkdir -p "$WORKFLOW_DIR"

WORKFLOWS=("Basic_Flux.json" "Mickmumpitz-SDXL_Consistent_Character.json" "Mickmumpitz-Flux_Consistent_Character.json")

for WORKFLOW in "${WORKFLOWS[@]}"; do
    if [ -f "/$WORKFLOW" ]; then
        if [ ! -f "$WORKFLOW_DIR/$WORKFLOW" ]; then
            mv "./$WORKFLOW" "$WORKFLOW_DIR"
            echo "$WORKFLOW copied."
        else
            echo "$WORKFLOW already exists in the target directory, skipping move."
        fi
    else
        echo "$WORKFLOW not found in the current directory."
    fi
done

# Workspace as main working directory
echo "cd $NETWORK_VOLUME" >> ~/.bashrc

# Patch ComfyUI main.py for legacy serialization
MAIN_PY="$NETWORK_VOLUME/ComfyUI/main.py"
if [ -f "$MAIN_PY" ]; then
    if ! grep -q "torch.serialization._legacy_serialization" "$MAIN_PY"; then
        echo "Patching main.py to enable legacy serialization"
        sed -i "2 a import torch
torch.serialization._legacy_serialization = True" "$MAIN_PY"
    fi
fi

# Start ComfyUI
echo "Starting ComfyUI"
python3 "$NETWORK_VOLUME/ComfyUI/main.py" --listen

