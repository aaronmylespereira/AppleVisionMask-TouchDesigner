#include "AppleVisionMask.h"
#include <iostream>
#include <algorithm>
#include <vector>

extern "C"
{
	DLLEXPORT
	void
	FillTOPPluginInfo(TD::TOP_PluginInfo *info)
	{
		info->setAPIVersion(TD::TOPCPlusPlusAPIVersion);
		info->executeMode = TD::TOP_ExecuteMode::CPUMem;

		info->customOPInfo.opType->setString("Applevisionmask");
		info->customOPInfo.opLabel->setString("Apple Vision Mask");
		info->customOPInfo.opIcon->setString("AVM");
		info->customOPInfo.authorName->setString("Author Name");
		info->customOPInfo.authorEmail->setString("email@email.com");

		info->customOPInfo.minInputs = 1;
		info->customOPInfo.maxInputs = 1;
	}

	DLLEXPORT
	TD::TOP_CPlusPlusBase*
	CreateTOPInstance(const TD::OP_NodeInfo* info, TD::TOP_Context *context)
	{
		return new AppleVisionMask(info, context);
	}

	DLLEXPORT
	void
	DestroyTOPInstance(TD::TOP_CPlusPlusBase* instance, TD::TOP_Context *context)
	{
		delete (AppleVisionMask*)instance;
	}
};

AppleVisionMask::AppleVisionMask(const TD::OP_NodeInfo* info, TD::TOP_Context* context) : myContext(context), myExecuteCount(0)
{
	// Initialize Vision Request with Default (Balanced = 1)
	currentQualityLevel = 1;
	segmentationRequest = [[VNGeneratePersonSegmentationRequest alloc] init];
	segmentationRequest.qualityLevel = VNGeneratePersonSegmentationRequestQualityLevelBalanced;
	segmentationRequest.outputPixelFormat = kCVPixelFormatType_OneComponent8;
}

AppleVisionMask::~AppleVisionMask()
{
}

void
AppleVisionMask::getGeneralInfo(TD::TOP_GeneralInfo* ginfo, const TD::OP_Inputs* inputs, void* reserved1)
{
	ginfo->cookEveryFrame = false; 
}

void
AppleVisionMask::setupParameters(TD::OP_ParameterManager* manager, void* reserved1)
{
	// Opacity
	TD::OP_NumericParameter np;
	np.name = "Opacity";
	np.label = "Background Opacity";
	np.defaultValues[0] = 1.0;
	np.minSliders[0] = 0.0;
	np.maxSliders[0] = 1.0;
	np.minValues[0] = 0.0;
	np.maxValues[0] = 1.0;
	np.clampMins[0] = true;
	np.clampMaxes[0] = true;
	manager->appendFloat(np);

	// Output Mode Menu
	TD::OP_StringParameter spMode;
	spMode.name = "Outputmode";
	spMode.label = "Output Mode";
	spMode.defaultValue = "Maskonly";
	const char* modeNames[] = { "Composited", "Maskonly" };
	const char* modeLabels[] = { "Composited (White Silhouette)", "Mask Only (Alpha 8-bit)" };
	manager->appendMenu(spMode, 2, modeNames, modeLabels);

	// Quality Level Menu
	TD::OP_StringParameter spQuality;
	spQuality.name = "Quality";
	spQuality.label = "Vision Quality";
	spQuality.defaultValue = "Balanced";
	const char* qualNames[] = { "Accurate", "Balanced", "Fast" };
	const char* qualLabels[] = { "Accurate", "Balanced", "Fast" };
	manager->appendMenu(spQuality, 3, qualNames, qualLabels);
}

void
AppleVisionMask::pulsePressed(const char* name, void* reserved1)
{
}

void
AppleVisionMask::execute(TD::TOP_Output* output, const TD::OP_Inputs* inputs, void* reserved1)
{
	myExecuteCount++;

	// 1. Handle Parameters
	double opacityVal = inputs->getParDouble("Opacity");
	int outputModeIndex = inputs->getParInt("Outputmode"); // 0 = Composite, 1 = Mask Only
	int qualityIndex = inputs->getParInt("Quality"); // 0=Accurate, 1=Balanced, 2=Fast

	// 2. Check for Quality Change
	if (qualityIndex != currentQualityLevel) {
		currentQualityLevel = qualityIndex;
		if (segmentationRequest) {
			segmentationRequest = nil; 
			segmentationRequest = [[VNGeneratePersonSegmentationRequest alloc] init];
			segmentationRequest.outputPixelFormat = kCVPixelFormatType_OneComponent8;
			
			switch (currentQualityLevel) {
				case 0: segmentationRequest.qualityLevel = VNGeneratePersonSegmentationRequestQualityLevelAccurate; break;
				case 1: segmentationRequest.qualityLevel = VNGeneratePersonSegmentationRequestQualityLevelBalanced; break;
				case 2: segmentationRequest.qualityLevel = VNGeneratePersonSegmentationRequestQualityLevelFast; break;
				default: segmentationRequest.qualityLevel = VNGeneratePersonSegmentationRequestQualityLevelBalanced; break;
			}
		}
	}

	// 3. Prepare LUT
	int opacityInt = (int)(opacityVal * 256.0); 

	// 4. Process Input
	if (inputs->getNumInputs() > 0)
	{
		const TD::OP_TOPInput* input = inputs->getInputTOP(0);
		TD::OP_TOPInputDownloadOptions downloadOpts;
		downloadOpts.pixelFormat = TD::OP_PixelFormat::BGRA8Fixed;
		downloadOpts.verticalFlip = true; 
		
		TD::OP_SmartRef<TD::OP_TOPDownloadResult> downloadResult = input->downloadTexture(downloadOpts, nullptr);

		if (downloadResult)
		{
			void* srcData = downloadResult->getData();
			TD::OP_TextureDesc srcDesc = downloadResult->textureDesc;
			size_t width = srcDesc.width;
			size_t height = srcDesc.height;
			size_t bytesPerRow = width * 4; 

			// Create CVPixelBuffer
			CVPixelBufferRef pixelBuffer = NULL;
			CVReturn result = CVPixelBufferCreateWithBytes(
				kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, srcData, bytesPerRow, NULL, NULL, NULL, &pixelBuffer
			);

			if (result != kCVReturnSuccess) {
				result = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, NULL, &pixelBuffer);
				if (result == kCVReturnSuccess) {
					CVPixelBufferLockBaseAddress(pixelBuffer, 0);
					void* destData = CVPixelBufferGetBaseAddress(pixelBuffer);
					size_t destBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
					uint8_t* sPtr = (uint8_t*)srcData;
					uint8_t* dPtr = (uint8_t*)destData;
					for(size_t y=0; y<height; ++y) {
						memcpy(dPtr + y*destBytesPerRow, sPtr + y*bytesPerRow, bytesPerRow);
					}
					CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
				}
			}

			if (result == kCVReturnSuccess && pixelBuffer != NULL)
			{
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
						uint8_t* maskBaseAddress = (uint8_t*)CVPixelBufferGetBaseAddress(maskPixelBuffer);
						size_t maskBytesPerRow = CVPixelBufferGetBytesPerRow(maskPixelBuffer);

						bool sameSize = (maskWidth == width && maskHeight == height);

						// Precompute fast scaling factors if needed
						uint32_t fpScaleX = 0, fpScaleY = 0;
						if (!sameSize) {
							fpScaleX = (uint32_t)((maskWidth << 16) / width);
							fpScaleY = (uint32_t)((maskHeight << 16) / height);
						}
						
						// --- OUTPUT MODE: MASK ONLY ---
						if (outputModeIndex == 1) 
						{
							uint64_t outSize = width * height * 1; 
							TD::OP_SmartRef<TD::TOP_Buffer> outBuffer = myContext->createOutputBuffer(outSize, TD::TOP_BufferFlags::None, nullptr);
							uint8_t* outData = (uint8_t*)outBuffer->data;

							if (sameSize) {
								// Fast Copy
								for (size_t y = 0; y < height; ++y) {
									uint8_t* maskRow = maskBaseAddress + (y * maskBytesPerRow);
									uint8_t* outRow = outData + (y * width);
									// Opacity Apply
									for (size_t x = 0; x < width; ++x) {
										outRow[x] = (maskRow[x] * opacityInt) >> 8;
									}
								}
							} else {
								// Bilinear Scaling
								for (size_t y = 0; y < height; ++y)
								{
									uint8_t* outRow = outData + (y * width);
									
									uint32_t fpY = y * fpScaleY;
									size_t y0 = fpY >> 16;
									size_t y1 = (y0 < maskHeight - 1) ? y0 + 1 : y0;
									uint32_t wy = (fpY & 0xFFFF) >> 8; // 0-255 weight

									uint8_t* row0 = maskBaseAddress + (y0 * maskBytesPerRow);
									uint8_t* row1 = maskBaseAddress + (y1 * maskBytesPerRow);

									uint32_t currentFpX = 0;
									for (size_t x = 0; x < width; ++x)
									{
										size_t x0 = currentFpX >> 16;
										size_t x1 = (x0 < maskWidth - 1) ? x0 + 1 : x0;
										uint32_t wx = (currentFpX & 0xFFFF) >> 8;
										
										// 4 Samples
										uint32_t v00 = row0[x0];
										uint32_t v01 = row0[x1];
										uint32_t v10 = row1[x0];
										uint32_t v11 = row1[x1];

										// Bilinear Math (Integer)
										// Lerp X
										uint32_t top = (v00 * (256 - wx) + v01 * wx) >> 8;
										uint32_t bot = (v10 * (256 - wx) + v11 * wx) >> 8;
										// Lerp Y
										uint32_t val = (top * (256 - wy) + bot * wy) >> 8;

										outRow[x] = (val * opacityInt) >> 8;
										currentFpX += fpScaleX;
									}
								}
							}
							
							TD::TOP_UploadInfo uploadInfo;
							uploadInfo.textureDesc.width = (uint32_t)width;
							uploadInfo.textureDesc.height = (uint32_t)height;
							uploadInfo.textureDesc.texDim = TD::OP_TexDim::e2D;
							uploadInfo.textureDesc.pixelFormat = TD::OP_PixelFormat::A8Fixed;
							uploadInfo.firstPixel = TD::TOP_FirstPixel::TopLeft;
							output->uploadBuffer(&outBuffer, uploadInfo, nullptr);
						}
						// --- OUTPUT MODE: COMPOSITED ---
						else 
						{
							uint64_t outSize = width * height * 4; // BGRA8
							TD::OP_SmartRef<TD::TOP_Buffer> outBuffer = myContext->createOutputBuffer(outSize, TD::TOP_BufferFlags::None, nullptr);
							uint32_t* outData = (uint32_t*)outBuffer->data;
							uint32_t white = 0x00FFFFFF; // BGR white

							if (sameSize) {
								for (size_t y = 0; y < height; ++y) {
									uint8_t* maskRow = maskBaseAddress + (y * maskBytesPerRow);
									uint32_t* outRow = outData + (y * width);
									for (size_t x = 0; x < width; ++x) {
										uint32_t a = (maskRow[x] * opacityInt) >> 8;
										outRow[x] = (a << 24) | white; 
									}
								}
							} else {
								// Bilinear Scaling
								for (size_t y = 0; y < height; ++y)
								{
									uint32_t* outRow = outData + (y * width);
									
									uint32_t fpY = y * fpScaleY;
									size_t y0 = fpY >> 16;
									size_t y1 = (y0 < maskHeight - 1) ? y0 + 1 : y0;
									uint32_t wy = (fpY & 0xFFFF) >> 8;

									uint8_t* row0 = maskBaseAddress + (y0 * maskBytesPerRow);
									uint8_t* row1 = maskBaseAddress + (y1 * maskBytesPerRow);

									uint32_t currentFpX = 0;
									for (size_t x = 0; x < width; ++x)
									{
										size_t x0 = currentFpX >> 16;
										size_t x1 = (x0 < maskWidth - 1) ? x0 + 1 : x0;
										uint32_t wx = (currentFpX & 0xFFFF) >> 8;
										
										uint32_t v00 = row0[x0];
										uint32_t v01 = row0[x1];
										uint32_t v10 = row1[x0];
										uint32_t v11 = row1[x1];

										uint32_t top = (v00 * (256 - wx) + v01 * wx) >> 8;
										uint32_t bot = (v10 * (256 - wx) + v11 * wx) >> 8;
										uint32_t val = (top * (256 - wy) + bot * wy) >> 8;

										uint32_t a = (val * opacityInt) >> 8;
										outRow[x] = (a << 24) | white;

										currentFpX += fpScaleX;
									}
								}
							}

							TD::TOP_UploadInfo uploadInfo;
							uploadInfo.textureDesc.width = (uint32_t)width;
							uploadInfo.textureDesc.height = (uint32_t)height;
							uploadInfo.textureDesc.texDim = TD::OP_TexDim::e2D;
							uploadInfo.textureDesc.pixelFormat = TD::OP_PixelFormat::BGRA8Fixed;
							uploadInfo.firstPixel = TD::TOP_FirstPixel::TopLeft;
							output->uploadBuffer(&outBuffer, uploadInfo, nullptr);
						}

						CVPixelBufferUnlockBaseAddress(maskPixelBuffer, kCVPixelBufferLock_ReadOnly);
					}
				}
				
				CVPixelBufferRelease(pixelBuffer);
			}
		}
	}
}