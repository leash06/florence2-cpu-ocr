import time
import numpy as np
import onnxruntime as ort

def run_inference_test():
    model_path = "export/weights/florence2_base_vision_encoder.onnx"
    
    print(f"Loading vision encoder from {model_path}...")
    # Initialize ONNX Runtime session with CPU provider
    session = ort.InferenceSession(model_path, providers=["CPUExecutionProvider"])
    
    # Get input details
    input_name = session.get_inputs()[0].name
    input_shape = session.get_inputs()[0].shape
    print(f"Model Input Name: {input_name}, Shape: {input_shape}")
    
    # Create dummy input matching the locked vision dimension (Batch=1, Channels=3, Height=768, Width=768)
    dummy_input = np.random.randn(1, 3, 768, 768).astype(np.float32)
    
    # Warmup run
    _ = session.run(None, {input_name: dummy_input})
    
    # Benchmark p50/p95 latency over 20 iterations
    latencies = []
    for _ in range(20):
        start = time.perf_counter()
        _ = session.run(None, {input_name: dummy_input})
        latencies.append((time.perf_counter() - start) * 1000) # Convert to ms
        
    p50 = np.percentile(latencies, 50)
    p95 = np.percentile(latencies, 95)
    
    print(f"--- Benchmark Results ---")
    print(f"p50 Latency: {p50:.2f} ms")
    print(f"p95 Latency: {p95:.2f} ms")

if __name__ == "__main__":
    run_inference_test()