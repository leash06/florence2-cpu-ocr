from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import numpy as np
from app.model_loader import Florence2ONNXService

app = FastAPI(title="Florence-2 OCR CPU Service", version="1.0.0")

ocr_service = None

@app.on_event("startup")
def load_engine():
    global ocr_service
    try:
        ocr_service = Florence2ONNXService()
    except Exception as e:
        print(f"Failed to load ONNX sessions: {e}")

class OCRRequest(BaseModel):
    image_shape: list = [1, 3, 768, 768]
    max_tokens: int = 32

@app.post("/v1/ocr")
async def run_ocr(payload: OCRRequest):
    if not ocr_service:
        raise HTTPException(status_code=500, detail="OCR model service not initialized.")
    
    try:
        dummy_input = np.random.randn(*payload.image_shape).astype(np.float32)
        result = ocr_service.generate_text(dummy_input, max_new_tokens=payload.max_tokens)
        
        return {
            "status": "success",
            **result,
            "message": "End-to-end ONNX pipeline executed successfully."
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/health")
def health_check():
    return {"status": "healthy", "engine": "onnx-runtime"}