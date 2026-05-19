import sys
from transformers import AutoTokenizer
import onnxruntime as ort
from huggingface_hub import hf_hub_download

MODEL_REPO = 'Cohee/distilbert-base-uncased-go-emotions-onnx'
# Download/load tokenizer
tokenizer = AutoTokenizer.from_pretrained(MODEL_REPO)

# Download ONNX model explicitly
model_path = hf_hub_download(repo_id=MODEL_REPO, filename="onnx/model.onnx")

# Initialize ONNX runtime session natively
session = ort.InferenceSession(model_path)

# Run classification
text = "I am so happy right now!"
inputs = tokenizer(text, return_tensors='np', truncation=True, max_length=512, padding=True)

ort_inputs = {
    "input_ids": inputs["input_ids"],
    "attention_mask": inputs["attention_mask"]
}

outputs = session.run(None, ort_inputs)
logits = outputs[0][0]
print("SUCCESS!")
print("Logits type:", type(logits))
print("Logits length:", len(logits))
