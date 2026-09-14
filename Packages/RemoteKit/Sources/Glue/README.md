# Glue — the only self-built surface in RemoteKit

Implements the Fusion seam: SessionBackend binding (open/stream/send/approve),
D1 sqlite adapter conforming the official `V2LocalStore` injectable slot, and D2
out-seam (translate AA item snapshot → upstream render vocabulary). No protocol
code lives here — that's all in AAV2/. [JO-2][JO-3][JO-6] legitimized, no upstream equiv.
