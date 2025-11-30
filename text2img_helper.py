import sys
import torch
from diffusers import DiffusionPipeline
import time

pipe = None

def progress_callback(pipe, step, timestep, callback_kwargs):
    total_steps = pipe.num_timesteps
    progress = int((step / total_steps) * 100)
    print(f"PROGRESS:{progress}", flush=True)
    return callback_kwargs

def load_model():
    global pipe
    print("PROGRESS:10", flush=True)
    pipe = DiffusionPipeline.from_pretrained(
        "UmitDataTeam/fine-diffusion",
        torch_dtype=torch.float32
    )
    print("PROGRESS:20", flush=True)
    pipe = pipe.to("cpu")
    pipe.enable_attention_slicing()
    print("PROGRESS:30", flush=True)

def generate_image(prompt, negative_prompt, steps, guidance, output_file):
    global pipe
    if pipe is None:
        load_model()
    print("PROGRESS:35", flush=True)
    result = pipe(
        prompt=prompt,
        negative_prompt=negative_prompt,
        num_inference_steps=int(steps),
        guidance_scale=float(guidance),
        height=512,
        width=512,
        callback_on_step_end=progress_callback
    )
    print("PROGRESS:95", flush=True)
    image = result.images[0]
    image.save(output_file)
    print("PROGRESS:100", flush=True)
    print("GENERATED", flush=True)

if __name__ == "__main__":
    if len(sys.argv) < 6:
        print("Error: Not enough arguments")
        sys.exit(1)
    prompt = sys.argv[1]
    negative_prompt = sys.argv[2]
    steps = sys.argv[3]
    guidance = sys.argv[4]
    output_file = sys.argv[5]
    generate_image(prompt, negative_prompt, steps, guidance, output_file)
