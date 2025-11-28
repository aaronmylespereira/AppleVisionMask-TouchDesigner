#include "TOP_CPlusPlusBase.h"
#include <vector>

#ifdef __OBJC__
#import <Vision/Vision.h>
#import <CoreVideo/CoreVideo.h>
#import <Foundation/Foundation.h>
#endif

class AppleVisionMask : public TD::TOP_CPlusPlusBase
{
public:
	AppleVisionMask(const TD::OP_NodeInfo* info, TD::TOP_Context* context);
	virtual ~AppleVisionMask();

	virtual void		getGeneralInfo(TD::TOP_GeneralInfo* ginfo, const TD::OP_Inputs* inputs, void* reserved1) override;
	virtual void		execute(TD::TOP_Output* output, const TD::OP_Inputs* inputs, void* reserved1) override;

	virtual void		setupParameters(TD::OP_ParameterManager* manager, void* reserved1) override;
	virtual void		pulsePressed(const char* name, void* reserved1) override;

private:

#ifdef __OBJC__
	VNGeneratePersonSegmentationRequest* segmentationRequest;
#else
	void* segmentationRequest;
#endif

	TD::TOP_Context*	myContext;
	int32_t				myExecuteCount;
	
	// State tracking for optimization
	int					currentQualityLevel; // 0=Accurate, 1=Balanced, 2=Fast
};