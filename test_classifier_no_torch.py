import sys
try:
    import torch
    print("Torch is installed, this test is invalid.")
    sys.exit(1)
except ImportError:
    pass

from transformers import AutoTokenizer
from optimum.onnxruntime import ORTModelForSequenceClassification

MODEL_REPO = 'Cohee/distilbert-base-uncased-go-emotions-onnx'
tokenizer = AutoTokenizer.from_pretrained(MODEL_REPO)
model = ORTModelForSequenceClassification.from_pretrained(MODEL_REPO)

inputs = tokenizer("I am so happy", return_tensors='np', truncation=True, max_length=512, padding=True)
outputs = model(**inputs)
print("SUCCESS!")
print(type(outputs.logits))
