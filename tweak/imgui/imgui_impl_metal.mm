// imgui_impl_metal.mm
// Dear ImGui Metal backend for iOS
// Renders ImGui draw data using Apple Metal APIs with inline shaders.

#import "imgui_impl_metal.h"
#import "imgui.h"

#import <Metal/Metal.h>
#import <simd/simd.h>
#import <time.h>

#pragma mark - Shader Source

static NSString* const kMetalShaderSource = @R"(
#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float4x4 projectionMatrix;
};

struct VertexIn {
    float2 position  [[attribute(0)]];
    float2 texCoords [[attribute(1)]];
    uchar4 color     [[attribute(2)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoords;
    float4 color;
};

vertex VertexOut vertex_main(VertexIn in [[stage_in]],
                             constant Uniforms &uniforms [[buffer(1)]]) {
    VertexOut out;
    out.position = uniforms.projectionMatrix * float4(in.position, 0.0, 1.0);
    out.texCoords = in.texCoords;
    out.color = float4(in.color) / float4(255.0);
    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]],
                              texture2d<float, access::sample> tex [[texture(0)]],
                              sampler samp [[sampler(0)]]) {
    return in.color * tex.sample(samp, in.texCoords);
}
)";

#pragma mark - Backend Data

struct MetalBuffer {
    id<MTLBuffer> buffer;
    NSUInteger    length;
    double        lastUseTime;
};

struct ImGui_ImplMetal_Data {
    id<MTLDevice>               device;
    id<MTLRenderPipelineState>  pipelineState;
    id<MTLDepthStencilState>    depthStencilState;
    id<MTLSamplerState>         samplerState;
    id<MTLTexture>              fontTexture;

    NSMutableArray<id<MTLBuffer>>* vertexBuffers;
    NSMutableArray<id<MTLBuffer>>* indexBuffers;

    MTLRenderPassDescriptor*    renderPassDescriptor;
    CFTimeInterval              lastFrameTime;
};

static ImGui_ImplMetal_Data* ImGui_ImplMetal_GetBackendData() {
    return ImGui::GetCurrentContext()
        ? (ImGui_ImplMetal_Data*)ImGui::GetIO().BackendRendererUserData
        : nullptr;
}

#pragma mark - Buffer Management

static id<MTLBuffer> ImGui_ImplMetal_DequeueBuffer(id<MTLDevice> device,
                                                    NSMutableArray<id<MTLBuffer>>* pool,
                                                    NSUInteger requiredSize) {
    // Look for a reusable buffer large enough
    for (NSUInteger i = 0; i < pool.count; i++) {
        id<MTLBuffer> buf = pool[i];
        if (buf.length >= requiredSize) {
            [pool removeObjectAtIndex:i];
            return buf;
        }
    }
    // Allocate a new one with some headroom
    NSUInteger allocSize = requiredSize + 4096;
    return [device newBufferWithLength:allocSize options:MTLResourceStorageModeShared];
}

#pragma mark - Pipeline Setup

static bool ImGui_ImplMetal_CreatePipelineState(ImGui_ImplMetal_Data* bd) {
    NSError* error = nil;

    id<MTLLibrary> library = [bd->device newLibraryWithSource:kMetalShaderSource
                                                      options:nil
                                                        error:&error];
    if (!library) {
        NSLog(@"[ImGui Metal] Failed to compile shaders: %@", error);
        return false;
    }

    id<MTLFunction> vertexFunction   = [library newFunctionWithName:@"vertex_main"];
    id<MTLFunction> fragmentFunction = [library newFunctionWithName:@"fragment_main"];

    // Vertex descriptor matching ImDrawVert layout
    MTLVertexDescriptor* vertexDescriptor = [MTLVertexDescriptor vertexDescriptor];

    // position: float2 at offset 0
    vertexDescriptor.attributes[0].format = MTLVertexFormatFloat2;
    vertexDescriptor.attributes[0].offset = IM_OFFSETOF(ImDrawVert, pos);
    vertexDescriptor.attributes[0].bufferIndex = 0;

    // texCoords: float2 at offset 8
    vertexDescriptor.attributes[1].format = MTLVertexFormatFloat2;
    vertexDescriptor.attributes[1].offset = IM_OFFSETOF(ImDrawVert, uv);
    vertexDescriptor.attributes[1].bufferIndex = 0;

    // color: uchar4 at offset 16
    vertexDescriptor.attributes[2].format = MTLVertexFormatUChar4Normalized;
    vertexDescriptor.attributes[2].offset = IM_OFFSETOF(ImDrawVert, col);
    vertexDescriptor.attributes[2].bufferIndex = 0;

    vertexDescriptor.layouts[0].stride = sizeof(ImDrawVert);
    vertexDescriptor.layouts[0].stepRate = 1;
    vertexDescriptor.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;

    // Pipeline state
    MTLRenderPipelineDescriptor* pipelineDesc = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDesc.vertexFunction   = vertexFunction;
    pipelineDesc.fragmentFunction = fragmentFunction;
    pipelineDesc.vertexDescriptor = vertexDescriptor;
    pipelineDesc.sampleCount      = 1;

    // Blending for transparent overlays
    pipelineDesc.colorAttachments[0].pixelFormat                 = MTLPixelFormatBGRA8Unorm;
    pipelineDesc.colorAttachments[0].blendingEnabled             = YES;
    pipelineDesc.colorAttachments[0].rgbBlendOperation           = MTLBlendOperationAdd;
    pipelineDesc.colorAttachments[0].alphaBlendOperation         = MTLBlendOperationAdd;
    pipelineDesc.colorAttachments[0].sourceRGBBlendFactor        = MTLBlendFactorSourceAlpha;
    pipelineDesc.colorAttachments[0].sourceAlphaBlendFactor      = MTLBlendFactorSourceAlpha;
    pipelineDesc.colorAttachments[0].destinationRGBBlendFactor   = MTLBlendFactorOneMinusSourceAlpha;
    pipelineDesc.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;

    pipelineDesc.depthAttachmentPixelFormat = MTLPixelFormatInvalid;

    bd->pipelineState = [bd->device newRenderPipelineStateWithDescriptor:pipelineDesc error:&error];
    if (!bd->pipelineState) {
        NSLog(@"[ImGui Metal] Failed to create pipeline state: %@", error);
        return false;
    }

    // Depth/stencil state (depth testing disabled)
    MTLDepthStencilDescriptor* depthDesc = [[MTLDepthStencilDescriptor alloc] init];
    depthDesc.depthWriteEnabled  = NO;
    depthDesc.depthCompareFunction = MTLCompareFunctionAlways;
    bd->depthStencilState = [bd->device newDepthStencilStateWithDescriptor:depthDesc];

    // Sampler state
    MTLSamplerDescriptor* samplerDesc = [[MTLSamplerDescriptor alloc] init];
    samplerDesc.minFilter    = MTLSamplerMinMagFilterLinear;
    samplerDesc.magFilter    = MTLSamplerMinMagFilterLinear;
    samplerDesc.mipFilter    = MTLSamplerMipFilterNotMipmapped;
    samplerDesc.sAddressMode = MTLSamplerAddressModeRepeat;
    samplerDesc.tAddressMode = MTLSamplerAddressModeRepeat;
    bd->samplerState = [bd->device newSamplerStateWithDescriptor:samplerDesc];

    return true;
}

#pragma mark - Public API

bool ImGui_ImplMetal_Init(id<MTLDevice> device) {
    ImGuiIO& io = ImGui::GetIO();
    IM_ASSERT(io.BackendRendererUserData == nullptr && "Already initialized");

    ImGui_ImplMetal_Data* bd = IM_NEW(ImGui_ImplMetal_Data)();
    bd->device = device;
    bd->vertexBuffers = [[NSMutableArray alloc] init];
    bd->indexBuffers  = [[NSMutableArray alloc] init];
    bd->lastFrameTime = CACurrentMediaTime();

    io.BackendRendererUserData = (void*)bd;
    io.BackendRendererName     = "imgui_impl_metal";
    io.BackendFlags |= ImGuiBackendFlags_RendererHasVtxOffset;

    return true;
}

void ImGui_ImplMetal_Shutdown() {
    ImGui_ImplMetal_Data* bd = ImGui_ImplMetal_GetBackendData();
    IM_ASSERT(bd != nullptr && "No Metal backend to shutdown");

    ImGui_ImplMetal_DestroyDeviceObjects();

    ImGuiIO& io = ImGui::GetIO();
    io.BackendRendererUserData = nullptr;
    io.BackendRendererName     = nullptr;

    IM_DELETE(bd);
}

void ImGui_ImplMetal_NewFrame(MTLRenderPassDescriptor* renderPassDescriptor) {
    ImGui_ImplMetal_Data* bd = ImGui_ImplMetal_GetBackendData();
    IM_ASSERT(bd != nullptr && "Metal backend not initialized");
    bd->renderPassDescriptor = renderPassDescriptor;

    if (!bd->pipelineState)
        ImGui_ImplMetal_CreateDeviceObjects(bd->device);
}

void ImGui_ImplMetal_RenderDrawData(ImDrawData* drawData,
                                     id<MTLCommandBuffer> commandBuffer,
                                     id<MTLRenderCommandEncoder> commandEncoder) {
    ImGui_ImplMetal_Data* bd = ImGui_ImplMetal_GetBackendData();
    if (!bd || !bd->pipelineState)
        return;

    // Avoid rendering when minimized
    if (drawData->DisplaySize.x <= 0.0f || drawData->DisplaySize.y <= 0.0f)
        return;

    [commandEncoder setCullMode:MTLCullModeNone];
    [commandEncoder setDepthStencilState:bd->depthStencilState];

    // Setup orthographic projection matrix
    float L = drawData->DisplayPos.x;
    float R = drawData->DisplayPos.x + drawData->DisplaySize.x;
    float T = drawData->DisplayPos.y;
    float B = drawData->DisplayPos.y + drawData->DisplaySize.y;
    float N = 0.0f;
    float F = 1.0f;

    float orthoProjection[4][4] = {
        { 2.0f/(R-L),    0.0f,          0.0f,  0.0f },
        { 0.0f,          2.0f/(T-B),    0.0f,  0.0f },
        { 0.0f,          0.0f,     1.0f/(F-N),  0.0f },
        { (R+L)/(L-R),   (T+B)/(B-T),  N/(N-F), 1.0f },
    };

    [commandEncoder setRenderPipelineState:bd->pipelineState];
    [commandEncoder setVertexBytes:&orthoProjection length:sizeof(orthoProjection) atIndex:1];
    [commandEncoder setFragmentSamplerState:bd->samplerState atIndex:0];

    // Will project scissor/clipping rectangles into framebuffer space
    ImVec2 clipOff   = drawData->DisplayPos;
    ImVec2 clipScale = drawData->FramebufferScale;

    // Render command lists
    for (int n = 0; n < drawData->CmdListsCount; n++) {
        const ImDrawList* cmdList = drawData->CmdLists[n];

        // Upload vertex buffer
        NSUInteger vertexBufferSize = (NSUInteger)cmdList->VtxBuffer.Size * sizeof(ImDrawVert);
        id<MTLBuffer> vertexBuffer = ImGui_ImplMetal_DequeueBuffer(bd->device,
                                                                    bd->vertexBuffers,
                                                                    vertexBufferSize);
        memcpy(vertexBuffer.contents, cmdList->VtxBuffer.Data, vertexBufferSize);

        // Upload index buffer
        NSUInteger indexBufferSize = (NSUInteger)cmdList->IdxBuffer.Size * sizeof(ImDrawIdx);
        id<MTLBuffer> indexBuffer = ImGui_ImplMetal_DequeueBuffer(bd->device,
                                                                   bd->indexBuffers,
                                                                   indexBufferSize);
        memcpy(indexBuffer.contents, cmdList->IdxBuffer.Data, indexBufferSize);

        [commandEncoder setVertexBuffer:vertexBuffer offset:0 atIndex:0];

        for (int cmd_i = 0; cmd_i < cmdList->CmdBuffer.Size; cmd_i++) {
            const ImDrawCmd* pcmd = &cmdList->CmdBuffer[cmd_i];

            if (pcmd->UserCallback) {
                if (pcmd->UserCallback != ImDrawCallback_ResetRenderState)
                    pcmd->UserCallback(cmdList, pcmd);
                else {
                    [commandEncoder setRenderPipelineState:bd->pipelineState];
                    [commandEncoder setVertexBytes:&orthoProjection length:sizeof(orthoProjection) atIndex:1];
                    [commandEncoder setFragmentSamplerState:bd->samplerState atIndex:0];
                }
                continue;
            }

            // Project scissor/clipping rectangles
            ImVec2 clipMin((pcmd->ClipRect.x - clipOff.x) * clipScale.x,
                           (pcmd->ClipRect.y - clipOff.y) * clipScale.y);
            ImVec2 clipMax((pcmd->ClipRect.z - clipOff.x) * clipScale.x,
                           (pcmd->ClipRect.w - clipOff.y) * clipScale.y);

            if (clipMax.x <= clipMin.x || clipMax.y <= clipMin.y)
                continue;

            MTLScissorRect scissorRect;
            scissorRect.x      = (NSUInteger)clipMin.x;
            scissorRect.y      = (NSUInteger)clipMin.y;
            scissorRect.width  = (NSUInteger)(clipMax.x - clipMin.x);
            scissorRect.height = (NSUInteger)(clipMax.y - clipMin.y);
            [commandEncoder setScissorRect:scissorRect];

            // Bind texture
            id<MTLTexture> texture = (__bridge id<MTLTexture>)(pcmd->GetTexID());
            if (texture) {
                [commandEncoder setFragmentTexture:texture atIndex:0];
            }

            // Draw
            [commandEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                                       indexCount:pcmd->ElemCount
                                        indexType:sizeof(ImDrawIdx) == 2
                                                      ? MTLIndexTypeUInt16
                                                      : MTLIndexTypeUInt32
                                      indexBuffer:indexBuffer
                                indexBufferOffset:pcmd->IdxOffset * sizeof(ImDrawIdx)
                                    instanceCount:1
                                       baseVertex:pcmd->VtxOffset
                                     baseInstance:0];
        }

        // Return buffers to pool for reuse
        [bd->vertexBuffers addObject:vertexBuffer];
        [bd->indexBuffers addObject:indexBuffer];
    }
}

#pragma mark - Font Texture

bool ImGui_ImplMetal_CreateFontsTexture(id<MTLDevice> device) {
    ImGui_ImplMetal_Data* bd = ImGui_ImplMetal_GetBackendData();
    ImGuiIO& io = ImGui::GetIO();

    unsigned char* pixels;
    int width, height;
    io.Fonts->GetTexDataAsRGBA32(&pixels, &width, &height);

    MTLTextureDescriptor* texDesc = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                     width:(NSUInteger)width
                                    height:(NSUInteger)height
                                 mipmapped:NO];
    texDesc.usage       = MTLTextureUsageShaderRead;
    texDesc.storageMode = MTLStorageModeShared;

    bd->fontTexture = [device newTextureWithDescriptor:texDesc];
    [bd->fontTexture replaceRegion:MTLRegionMake2D(0, 0, (NSUInteger)width, (NSUInteger)height)
                       mipmapLevel:0
                         withBytes:pixels
                       bytesPerRow:(NSUInteger)width * 4];

    io.Fonts->SetTexID((__bridge void*)bd->fontTexture);

    return true;
}

void ImGui_ImplMetal_DestroyFontsTexture() {
    ImGui_ImplMetal_Data* bd = ImGui_ImplMetal_GetBackendData();
    if (bd) {
        ImGuiIO& io = ImGui::GetIO();
        io.Fonts->SetTexID(nullptr);
        bd->fontTexture = nil;
    }
}

#pragma mark - Device Objects

bool ImGui_ImplMetal_CreateDeviceObjects(id<MTLDevice> device) {
    ImGui_ImplMetal_Data* bd = ImGui_ImplMetal_GetBackendData();
    if (!bd)
        return false;

    if (!ImGui_ImplMetal_CreatePipelineState(bd))
        return false;

    ImGui_ImplMetal_CreateFontsTexture(device);

    return true;
}

void ImGui_ImplMetal_DestroyDeviceObjects() {
    ImGui_ImplMetal_Data* bd = ImGui_ImplMetal_GetBackendData();
    if (!bd)
        return;

    ImGui_ImplMetal_DestroyFontsTexture();

    bd->pipelineState     = nil;
    bd->depthStencilState = nil;
    bd->samplerState      = nil;

    [bd->vertexBuffers removeAllObjects];
    [bd->indexBuffers removeAllObjects];
}
