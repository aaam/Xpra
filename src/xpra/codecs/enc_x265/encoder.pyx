# This file is part of Xpra.
# Copyright (C) 2014 Antoine Martin <antoine@devloop.org.uk>
# Xpra is released under the terms of the GNU GPL v2, or, at your option, any
# later version. See the file COPYING for details.

import time
import os

from xpra.log import Logger
log = Logger("encoder", "x265")

from xpra.codecs.codec_constants import get_subsampling_divs, RGB_FORMATS, codec_spec

cdef extern from "string.h":
    void * memcpy ( void * destination, void * source, size_t num )
    void * memset ( void * ptr, int value, size_t num )

from libc.stdint cimport int64_t, uint64_t, uint8_t, uint32_t

cdef extern from *:
    ctypedef unsigned long size_t

cdef extern from "stdint.h":
    pass
cdef extern from "inttypes.h":
    pass

cdef extern from "Python.h":
    ctypedef int Py_ssize_t
    ctypedef object PyObject
    int PyObject_AsReadBuffer(object obj, void ** buffer, Py_ssize_t * buffer_len) except -1


cdef extern from "x265.h":

    const char *x265_version_str
    int x265_max_bit_depth

    ctypedef struct rc:
        int         rateControlMode                 #explicit mode of rate-control, must be one of the X265_RC_METHODS enum values
        int         qp                              #base QP to use for Constant QP rate control
        int         bitrate                         #target bitrate for Average BitRate
        double      rateTolerance                   #the degree of rate fluctuation that x265 tolerates
        double      qCompress                       #sets the quantizer curve compression factor
        double      ipFactor
        double      pbFactor
        int         qpStep                          #Max QP difference between frames
        double      rfConstant
        int         aqMode                          #enable adaptive quantization
        double      aqStrength                      #sets the strength of AQ bias towards low detail macroblocks
        int         vbvMaxBitrate                   #sets the maximum rate the VBV buffer should be assumed to refill at
        int         vbvBufferSize                   #sets the size of the VBV buffer in kilobits. Default is zero
        double      vbvBufferInit                   #sets how full the VBV buffer must be before playback starts
        int         cuTree                          #enable CUTree ratecontrol
        double      rfConstantMax                   #in CRF mode, maximum CRF as caused by VBV

    ctypedef struct x265_param:
        int         logLevel
        const char  *csvfn
        int         bEnableWavefront                #enable wavefront parallel processing
        int         poolNumThreads                  #number of threads to allocate for thread pool
        int         frameNumThreads                 #number of concurrently encoded frames

        int         sourceWidth                     #source width in pixels
        int         sourceHeight                    #source height in pixels
        int         internalBitDepth                #Internal encoder bit depth
        int         internalCsp                     #color space of internal pictures


        int         fpsNum                          #framerate numerator
        int         fpsDenom                        #framerate denominator

        uint32_t    tuQTMaxInterDepth               #1 (speed) to 3 (efficient)
        uint32_t    tuQTMaxIntraDepth               #1 (speed) to 3 (efficient)
        int         bOpenGOP                        #Enable Open GOP referencing
        int         keyframeMin                     #Minimum intra period in frames
        int         keyframeMax                     #Maximum intra period in frames
        int         maxNumReferences                #1 (speed) to 16 (efficient)
        int         bframes                         #Max number of consecutive B-frames
        int         bBPyramid                       #use some B frames as a motion reference for the surrounding B frames
        int         lookaheadDepth                  #Number of frames to use for lookahead, determines encoder latency
        int         bFrameAdaptive                  #0 - none, 1 - fast, 2 - full (trellis) adaptive B frame scheduling
        int         bFrameBias                      #value which is added to the cost estimate of B frames
        int         scenecutThreshold               #how aggressively to insert extra I frames
        int         bEnableConstrainedIntra         #enable constrained intra prediction
        int         bEnableStrongIntraSmoothing     #enable strong intra smoothing for 32x32 blocks where the reference samples are flat

        int         searchMethod                    #ME search method (DIA, HEX, UMH, STAR, FULL)
        int         subpelRefine                    #amount of effort performed during subpel refine
        int         searchRange                     #ME search range
        uint32_t    maxNumMergeCand                 #Max number of merge candidates
        int         bEnableWeightedPred             #enable weighted prediction in P slices
        int         bEnableWeightedBiPred           #enable bi-directional weighted prediction in B slices
        int         bEnableAMP                      #enable asymmetrical motion predictions
        int         bEnableRectInter                #enable rectangular motion prediction partitions
        int         bEnableCbfFastMode              #enable the use of `coded block flags`
        int         bEnableEarlySkip                #enable early skip decisions
        int         rdPenalty                       #penalty to the estimated cost of 32x32 intra blocks in non-intra slices (0 to 2)
        int         rdLevel                         #level of rate distortion optimizations to perform (0-fast, X265_RDO_LEVEL-efficient)
        int         bEnableSignHiding               #enable the implicit signaling of the sign bit of the last coefficient of each transform unit
        int         bEnableTransformSkip            #allow intra coded blocks to be encoded directly as residual
        int         bEnableTSkipFast                #enable a faster determination of whether skippig the DCT transform will be beneficial
        int         bEnableLoopFilter               #enable the deblocking loop filter
        int         bEnableSAO                      #enable the Sample Adaptive Offset loop filter
        int         saoLcuBoundary                  #select the method in which SAO deals with deblocking boundary pixels
        int         saoLcuBasedOptimization         #select the scope of the SAO optimization
        int         cbQpOffset                      #small signed integer which offsets the QP used to quantize the Cb chroma residual
        int         crQpOffset                      #small signed integer which offsets the QP used to quantize the Cr chroma residual

        rc          rc


    ctypedef struct x265_encoder:
        pass
    ctypedef struct x265_picture:
        void        *planes[3]
        int         stride[3]
        int         bitDepth
        int         sliceType
        int         poc
        int         colorSpace
        int64_t     pts
        int64_t     dts
        void        *userData

    ctypedef struct x265_nal:
        uint32_t    type                            #NalUnitType
        uint32_t    sizeBytes                       #size in bytes
        uint8_t*    payload

    ctypedef struct x265_stats:
        double    globalPsnrY
        double    globalPsnrU
        double    globalPsnrV
        double    globalPsnr
        double    globalSsim
        double    elapsedEncodeTime                 # wall time since encoder was opened
        double    elapsedVideoTime                  # encoded picture count / frame rate
        double    bitrate                           # accBits / elapsed video time
        uint32_t  encodedPictureCount               # number of output pictures thus far
        uint32_t  totalWPFrames                     # number of uni-directional weighted frames used
        uint64_t  accBits                           # total bits output thus far

    #X265_ME_METHODS:
    int X265_DIA_SEARCH,
    int X265_HEX_SEARCH
    int X265_UMH_SEARCH
    int X265_STAR_SEARCH
    int X265_FULL_SEARCH

    int X265_LOG_NONE
    int X265_LOG_ERROR
    int X265_LOG_WARNING
    int X265_LOG_INFO
    int X265_LOG_DEBUG

    #frame type:
    int X265_TYPE_AUTO                              # Let x265 choose the right type
    int X265_TYPE_IDR
    int X265_TYPE_I
    int X265_TYPE_P
    int X265_TYPE_BREF                              # Non-disposable B-frame
    int X265_TYPE_B

    #input formats defined (only I420 and I444 are supported)
    int X265_CSP_I400                               # yuv 4:0:0 planar
    int X265_CSP_I420                               # yuv 4:2:0 planar
    int X265_CSP_I422                               # yuv 4:2:2 planar
    int X265_CSP_I444                               # yuv 4:4:4 planar
    int X265_CSP_NV12                               # yuv 4:2:0, with one y plane and one packed u+v
    int X265_CSP_NV16                               # yuv 4:2:2, with one y plane and one packed u+v
    int X265_CSP_BGR                                # packed bgr 24bits
    int X265_CSP_BGRA                               # packed bgr 32bits
    int X265_CSP_RGB                                # packed rgb 24bits

    #rate tolerance:
    int X265_RC_ABR
    int X265_RC_CQP
    int X265_RC_CRF

    x265_param *x265_param_alloc()
    void x265_param_free(x265_param *)
    void x265_param_default(x265_param *param)

    x265_encoder *x265_encoder_open(x265_param *)
    void x265_encoder_close(x265_encoder *encoder)
    void x265_cleanup()

    #static const char * const x265_profile_names[] = { "main", "main10", "mainstillpicture", 0 };
    #static const char * const x265_preset_names[] = { "ultrafast", "superfast", "veryfast", "faster", "fast", "medium", "slow", "slower", "veryslow", "placebo", 0 };
    #static const char * const x265_tune_names[] = { "psnr", "ssim", "zero-latency", 0 };

    int x265_param_apply_profile(x265_param *param, const char *profile)
    int x265_param_default_preset(x265_param *param, const char *preset, const char *tune)

    x265_picture *x265_picture_alloc()
    void x265_picture_free(x265_picture *pic)
    void x265_picture_init(x265_param *param, x265_picture *pic)

    int x265_encoder_headers(x265_encoder *encoder, x265_nal **pp_nal, uint32_t *pi_nal) nogil
    int x265_encoder_encode(x265_encoder *encoder, x265_nal **pp_nal, uint32_t *pi_nal, x265_picture *pic_in, x265_picture *pic_out) nogil

cdef char *PROFILE_MAIN     = "main"
cdef char *PROFILE_MAIN10   = "main10"
cdef char *PROFILE_MAINSTILLPICTURE = "mainstillpicture"
PROFILES = [PROFILE_MAIN, PROFILE_MAIN10, PROFILE_MAINSTILLPICTURE]

#as per the source code: only these two formats are supported:
COLORSPACES = ["YUV420P", "YUV444P"]


def init_module():
    #nothing to do!
    pass

def get_version():
    return x265_version_str

def get_type():
    return "x265"

def get_encodings():
    return ["h265"]

def get_colorspaces():
    return COLORSPACES

def get_output_colorspaces():
    #same as input
    return COLORSPACES


def get_spec(encoding, colorspace):
    assert encoding in get_encodings(), "invalid encoding: %s (must be one of %s" % (encoding, get_encodings())
    assert colorspace in COLORSPACES, "invalid colorspace: %s (must be one of %s)" % (colorspace, COLORSPACES.keys())
    #ratings: quality, speed, setup cost, cpu cost, gpu cost, latency, max_w, max_h, max_pixels
    #we can handle high quality and any speed
    #setup cost is moderate (about 10ms)
    return codec_spec(Encoder, codec_type=get_type(), encoding=encoding,
                      min_w=64, min_h=64,
                      setup_cost=70, width_mask=0xFFFE, height_mask=0xFFFE)


cdef class Encoder:
    cdef x265_param *param
    cdef x265_encoder *context
    cdef int width
    cdef int height
    cdef object src_format
    cdef object preset
    cdef char *profile
    cdef int quality
    cdef int speed
    cdef double time
    cdef int frames
    cdef long first_frame_timestamp

    cdef object __weakref__

    def init_context(self, int width, int height, src_format, encoding, int quality, int speed, scaling, options):    #@DuplicatedSignature
        global COLORSPACES
        assert src_format in COLORSPACES, "invalid source format: %s, must be one of: %s" % (src_format, COLORSPACES)
        assert encoding=="h265", "invalid encoding: %s" % encoding
        self.width = width
        self.height = height
        self.quality = quality
        self.speed = speed
        self.src_format = src_format
        self.frames = 0
        self.time = 0
        self.preset = "ultrafast"
        self.profile = PROFILE_MAIN
        self.init_encoder()

    cdef init_encoder(self):
        cdef const char *preset
        cdef r

        self.param = x265_param_alloc()
        assert self.param!=NULL
        x265_param_default(self.param)
        if x265_param_apply_profile(self.param, self.profile)!=0:
            raise Exception("failed to set profile: %s" % self.profile)
        if x265_param_default_preset(self.param, self.preset, "zero-latency")!=0:
            raise Exception("failed to set preset: %s" % self.preset)

        self.param.sourceWidth = self.width
        self.param.sourceHeight = self.height
        self.param.frameNumThreads = 1
        self.param.logLevel = X265_LOG_INFO
        self.param.bOpenGOP = 1
        self.param.searchMethod = X265_HEX_SEARCH
        self.param.fpsNum = 1
        self.param.fpsDenom = 1
        #force zero latency:
        self.param.bframes = 0
        self.param.bFrameAdaptive = 0
        self.param.lookaheadDepth = 0
        if False:
            #unused settings:
            self.param.internalBitDepth = 8
            self.param.searchRange = 30
            self.param.keyframeMin = 0
            self.param.keyframeMax = -1
            self.param.tuQTMaxInterDepth = 2
            self.param.tuQTMaxIntraDepth = 2
            self.param.maxNumReferences = 1
            self.param.bBPyramid = 0
            self.param.bFrameBias = 0
            self.param.scenecutThreshold = 40
            self.param.bEnableConstrainedIntra = 0
            self.param.bEnableStrongIntraSmoothing = 1
            self.param.maxNumMergeCand = 2
            self.param.subpelRefine = 5
            self.param.bEnableWeightedPred = 0
            self.param.bEnableWeightedBiPred = 0
            self.param.bEnableAMP = 0
            self.param.bEnableRectInter = 1
            self.param.bEnableCbfFastMode = 1
            self.param.bEnableEarlySkip = 1
            self.param.rdPenalty = 2
            self.param.rdLevel = 0
            self.param.bEnableSignHiding = 0
            self.param.bEnableTransformSkip = 0
            self.param.bEnableTSkipFast = 1
            self.param.bEnableLoopFilter = 0
            self.param.bEnableSAO = 0
            self.param.saoLcuBoundary = 0
            self.param.saoLcuBasedOptimization = 0
            self.param.cbQpOffset = 0
            self.param.crQpOffset = 0

        self.param.rc.bitrate = 5000
        self.param.rc.rateControlMode = X265_RC_ABR

        if self.src_format=="YUV420P":
            self.param.internalCsp = X265_CSP_I420
        else:
            assert self.src_format=="YUV444P"
            self.param.internalCsp = X265_CSP_I444
        self.context = x265_encoder_open(self.param)
        log("init_encoder() x265 context=%#x", <unsigned long> self.context)
        assert self.context!=NULL,  "context initialization failed for format %s" % self.src_format

    def get_info(self):
        cdef float pps
        if self.profile is None:
            return {}
        info = {"profile"   : self.profile,
                #"preset"    : get_preset_names()[self.preset],
                "frames"    : self.frames,
                "width"     : self.width,
                "height"    : self.height,
                "speed"     : self.speed,
                "quality"   : self.quality,
                "src_format": self.src_format}
        if self.frames>0 and self.time>0:
            pps = float(self.width) * float(self.height) * float(self.frames) / self.time
            info["total_time_ms"] = int(self.time*1000.0)
            info["pixels_per_second"] = int(pps)
        return info

    def __str__(self):
        if self.src_format is None:
            return "x264_encoder(uninitialized)"
        return "x264_encoder(%s - %sx%s)" % (self.src_format, self.width, self.height)

    def is_closed(self):
        return self.context==NULL

    def get_encoding(self):
        return "h265"

    def __dealloc__(self):
        self.clean()

    def get_width(self):
        return self.width

    def get_height(self):
        return self.height

    def get_type(self):                     #@DuplicatedSignature
        return  "x265"

    def get_src_format(self):
        return self.src_format

    def clean(self):                        #@DuplicatedSignature
        log("clean() x265 param=%#x, context=%#x", <unsigned long> self.param, <unsigned long> self.context)
        if self.param!=NULL:
            x265_param_free(self.param)
            self.param = NULL
        if self.context!=NULL:
            x265_encoder_close(self.context)
            self.context = NULL


    def compress_image(self, image, options={}):
        cdef x265_nal *nal
        cdef uint32_t nnal = 0
        cdef int r = 0
        cdef x265_picture *pic_out
        cdef x265_picture *pic_in
        cdef int frame_size = 0

        cdef uint8_t *pic_buf
        cdef Py_ssize_t pic_buf_len = 0
        cdef char *out

        cdef int quality_override = options.get("quality", -1)
        cdef int speed_override = options.get("speed", -1)
        cdef int saved_quality = self.quality
        cdef int saved_speed = self.speed
        cdef int i                        #@DuplicatedSignature

        assert self.context!=NULL
        start = time.time()
        data = []
        log("x265.compress_image(%s, %s)", image, options)
        if self.frames==0:
            #first frame, record pts:
            self.first_frame_timestamp = image.get_timestamp()
            #send headers (not needed?)
            if x265_encoder_headers(self.context, &nal, &nnal)<0:
                log.error("x265 encoding headers error: %s", r)
                return None
            log("x265 header nals: %s", nnal)
            for i in range(nnal):
                out = <char *>nal[i].payload
                data.append(out[:nal[i].sizeBytes])
                log("x265 header[%s]: %s bytes", i, nal[i].sizeBytes)

        pixels = image.get_pixels()
        istrides = image.get_rowstride()

        pic_in = x265_picture_alloc()
        assert pic_in!=NULL
        x265_picture_init(self.param, pic_in)

        pic_out = x265_picture_alloc()
        assert pic_out!=NULL

        assert len(pixels)==3, "image pixels does not have 3 planes! (found %s)" % len(pixels)
        assert len(istrides)==3, "image strides does not have 3 values! (found %s)" % len(istrides)
        for i in range(3):
            PyObject_AsReadBuffer(pixels[i], <const void**> &pic_buf, &pic_buf_len)
            pic_in.planes[i] = pic_buf
            pic_in.stride[i] = istrides[i]
        pic_in.pts = image.get_timestamp()-self.first_frame_timestamp

        with nogil:
            r = x265_encoder_encode(self.context, &nal, &nnal, pic_in, pic_out)
        log("x265 picture encode returned %s (nnal=%s)", r, nnal)
        x265_picture_free(pic_in)
        if r==0:
            r = x265_encoder_encode(self.context, &nal, &nnal, NULL, pic_out)
            log("x265 picture encode returned %s (nnal=%s)", r, nnal)
        if r<=0:
            x265_picture_free(pic_out)
            log.error("x265 encoding error: %s", r)
            return None
        frame_size = nal[0].sizeBytes
        out = <char *>nal[0].payload
        data.append(out[:frame_size])
        x265_picture_free(pic_out)
        #quality and speed are not used (yet):
        client_options = {
                "frame"     : self.frames,
                "pts"     : image.get_timestamp()-self.first_frame_timestamp,
                #"quality"   : q,
                #"speed"     : s,
                }
        end = time.time()
        self.time += end-start
        self.frames += 1
        log("x265 compressed data size: %s, client options=%s", frame_size, client_options)
        return  "".join(data), client_options


    def set_encoding_speed(self, int pct):
        pass

    def set_encoding_quality(self, int pct):
        pass