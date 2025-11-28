#include "TOP_CPlusPlusBase.h"

#ifdef __OBJC__
#include <Vision/Vision.h>
#include <CoreVideo/CoreVideo.h>
#endif

class MyBackgroundRemover : public TD::TOP_CPlusPlusBase
{
public:
	MyBackgroundRemover(const TD::OP_NodeInfo* info, TD::TOP_Context* context);
	virtual ~MyBackgroundRemover();

	virtual void		getGeneralInfo(TD::TOP_GeneralInfo* ginfo, const TD::OP_Inputs* inputs, void* reserved1) override;
	virtual void		execute(TD::TOP_Output* output, const TD::OP_Inputs* inputs, void* reserved1) override;

	virtual void		setupParameters(TD::OP_ParameterManager* manager, void* reserved1) override;
	virtual void		pulsePressed(const char* name, void* reserved1) override;

private:

#ifdef __OBJC__
	VNGeneratePersonSegmentationRequest* segmentationRequest;
	VNImageRequestHandler* requestHandler;
#else
	void* segmentationRequest;
	void* requestHandler;
#endif

	int32_t				myExecuteCount;
	TD::TOP_Context*	myContext;
};
