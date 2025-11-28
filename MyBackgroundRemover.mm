#include "MyBackgroundRemover.h"
#include <iostream>

// These functions are basic C function, which the DLL loader can find
// much easier than finding a C++ Class.
// The DLLEXPORT prefix is needed so the compile exports these functions from the .dll
// you are creating
extern "C"
{
	DLLEXPORT
	void
	FillTOPPluginInfo(TD::TOP_PluginInfo *info)
	{
		// This must always be set to this constant
		info->setAPIVersion(TD::TOPCPlusPlusAPIVersion);

		// The opType is the unique name for this TOP. It must start with a capital A-Z character, and all the following characters must lower case
		// or numbers (a-z, 0-9)
		info->customOPInfo.opType->setString("Mybackgroundremover");

		// The opLabel is the text that will show up in the OP Create Dialog
		info->customOPInfo.opLabel->setString("My Background Remover");

		// Icon to show in the OP Create Dialog
		info->customOPInfo.opIcon->setString("MBR");

		// Information about the author of this OP
		info->customOPInfo.authorName->setString("Author Name");
		info->customOPInfo.authorEmail->setString("email@email.com");

		// This TOP works with 0 or 1 inputs connected
		info->customOPInfo.minInputs = 0;
		info->customOPInfo.maxInputs = 1;
	}

	DLLEXPORT
	TD::TOP_CPlusPlusBase*
	CreateTOPInstance(const TD::OP_NodeInfo* info, TD::TOP_Context *context)
	{
		// Return a new instance of your class every time this is called.
		// It will be called once per TOP that is using the .dll
		return new MyBackgroundRemover(info, context);
	}

	DLLEXPORT
	void
	DestroyTOPInstance(TD::TOP_CPlusPlusBase* instance, TD::TOP_Context *context)
	{
		// Delete the instance here, this will be called when
		// TouchDesigner is shutting down, or the TOP using the .dll is deleted
		delete (MyBackgroundRemover*)instance;
	}
};

MyBackgroundRemover::MyBackgroundRemover(const TD::OP_NodeInfo* info, TD::TOP_Context* context) : myExecuteCount(0), myContext(context)
{
	// Initialize Vision Request
	segmentationRequest = [[VNGeneratePersonSegmentationRequest alloc] init];
	segmentationRequest.qualityLevel = VNGeneratePersonSegmentationRequestQualityLevelBalanced;
	segmentationRequest.outputPixelFormat = kCVPixelFormatType_OneComponent8;
}

MyBackgroundRemover::~MyBackgroundRemover()
{
	// ARC handles release of segmentationRequest and requestHandler
}

void
MyBackgroundRemover::getGeneralInfo(TD::TOP_GeneralInfo* ginfo, const TD::OP_Inputs* inputs, void* reserved1)
{
	ginfo->cookEveryFrame = false; // Cook only when input changes
}

void
MyBackgroundRemover::setupParameters(TD::OP_ParameterManager* manager, void* reserved1)
{
	// No parameters for now
}

void
MyBackgroundRemover::pulsePressed(const char* name, void* reserved1)
{
}

void
MyBackgroundRemover::execute(TD::TOP_Output* output, const TD::OP_Inputs* inputs, void* reserved1)
{
	myExecuteCount++;

	if (inputs->getNumInputs() > 0)
	{
		const TD::OP_TOPInput* input = inputs->getInputTOP(0);
		
		// Prepare download options
		TD::OP_TOPInputDownloadOptions downloadOpts;
		downloadOpts.pixelFormat = TD::OP_PixelFormat::BGRA8Fixed;
		downloadOpts.verticalFlip = true; // Flip to match Vision/Image coordinates if needed. Usually Vision expects Top-Left. TD is Bottom-Left. Flip might be needed.

		// Download Input Texture
		TD::OP_SmartRef<TD::OP_TOPDownloadResult> downloadResult = input->downloadTexture(downloadOpts, nullptr);

		if (downloadResult)
		{
			void* srcData = downloadResult->getData();
			uint64_t dataSize = downloadResult->size;
			TD::OP_TextureDesc srcDesc = downloadResult->textureDesc;
			
			size_t width = srcDesc.width;
			size_t height = srcDesc.height;
			size_t bytesPerRow = width * 4; // BGRA8

			// Create CVPixelBuffer from input data
			CVPixelBufferRef pixelBuffer = NULL;
			CVReturn result = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, NULL, &pixelBuffer);

			if (result == kCVReturnSuccess && pixelBuffer != NULL)
			{
				CVPixelBufferLockBaseAddress(pixelBuffer, 0);
				void* baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer);
				size_t destBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
				
				// Copy data line by line if strides differ, or memcpy if compatible
				// srcData is tightly packed usually. dest might have padding.
				
				uint8_t* srcPtr = (uint8_t*)srcData;
				uint8_t* destPtr = (uint8_t*)baseAddress;
				
				for(int y=0; y<height; y++) {
					memcpy(destPtr + y * destBytesPerRow, srcPtr + y * bytesPerRow, bytesPerRow);
				}
				
				CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);

				// Perform Vision Request
				VNImageRequestHandler* handler = [[VNImageRequestHandler alloc] initWithCVPixelBuffer:pixelBuffer options:@{}];
				NSError* error = nil;
				[handler performRequests:@[segmentationRequest] error:&error];

				if (!error && [segmentationRequest results].count > 0)
				{
					VNPixelBufferObservation* observation = [[segmentationRequest results] firstObject];
					CVPixelBufferRef maskPixelBuffer = observation.pixelBuffer;

					if (maskPixelBuffer)
					{
						CVPixelBufferLockBaseAddress(maskPixelBuffer, kCVPixelBufferLock_ReadOnly);
						
						size_t maskWidth = CVPixelBufferGetWidth(maskPixelBuffer);
						size_t maskHeight = CVPixelBufferGetHeight(maskPixelBuffer);
						void* maskBaseAddress = CVPixelBufferGetBaseAddress(maskPixelBuffer);
						size_t maskBytesPerRow = CVPixelBufferGetBytesPerRow(maskPixelBuffer);
						
						// Allocate Output Buffer
						// We will output BGRA where RGB is input and A is mask.
						// Note: Mask size might differ from input size. We should scale if necessary.
						// For 'Balanced' quality, mask is typically input resolution, but let's handle resizing nearest neighbor if needed or just assume same for MVP.
						// If sizes differ, we'll just output the mask as is, or resizing.
						// Let's output at input resolution for simplicity.
						
						uint64_t outSize = width * height * 4; // BGRA8
						TD::OP_SmartRef<TD::TOP_Buffer> outBuffer = myContext->createOutputBuffer(outSize, TD::TOP_BufferFlags::None, nullptr);
						
						uint8_t* outData = (uint8_t*)outBuffer->data;
						
						// Fill Output
						// Copy RGB from input, A from mask (resampled nearest neighbor if size diff)
						
						float maskScaleX = (float)maskWidth / width;
						float maskScaleY = (float)maskHeight / height;
						
						uint8_t* maskPtr = (uint8_t*)maskBaseAddress;

						for (int y = 0; y < height; y++)
						{
							for (int x = 0; x < width; x++)
							{
								int srcIdx = (y * width + x) * 4;
								int outIdx = srcIdx; // same layout
								
								// Copy BGR
								outData[outIdx + 0] = srcPtr[srcIdx + 0];
								outData[outIdx + 1] = srcPtr[srcIdx + 1];
								outData[outIdx + 2] = srcPtr[srcIdx + 2];
								
								// Sample Mask
								int maskX = (int)(x * maskScaleX);
								int maskY = (int)(y * maskScaleY);
								if (maskX >= maskWidth) maskX = maskWidth - 1;
								if (maskY >= maskHeight) maskY = maskHeight - 1;
								
								// Mask is OneComponent8 (uint8)
								// Mask usually has stride padding too
								uint8_t maskVal = maskPtr[maskY * maskBytesPerRow + maskX];
								
								outData[outIdx + 3] = maskVal;
							}
						}

						CVPixelBufferUnlockBaseAddress(maskPixelBuffer, kCVPixelBufferLock_ReadOnly);
						
						// Upload
						TD::TOP_UploadInfo uploadInfo;
						uploadInfo.textureDesc.width = (uint32_t)width;
						uploadInfo.textureDesc.height = (uint32_t)height;
						uploadInfo.textureDesc.texDim = TD::OP_TexDim::e2D;
						uploadInfo.textureDesc.pixelFormat = TD::OP_PixelFormat::BGRA8Fixed;
						uploadInfo.firstPixel = TD::TOP_FirstPixel::TopLeft;

						output->uploadBuffer(&outBuffer, uploadInfo, nullptr);
					}
				}
				
				CVPixelBufferRelease(pixelBuffer);
			}
		}
	}
}