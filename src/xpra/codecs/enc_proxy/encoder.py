# This file is part of Xpra.
# Copyright (C) 2014 Antoine Martin <antoine@devloop.org.uk>
# Xpra is released under the terms of the GNU GPL v2, or, at your option, any
# later version. See the file COPYING for details.

import time

from xpra.log import Logger, debug_if_env
log = Logger()
debug = debug_if_env(log, "XPRA_PROXYVIDEO_DEBUG")
error = log.error

from xpra.codecs.image_wrapper import ImageWrapper
from xpra.deque import maxdeque


def get_version():
    return (0, 1)

def get_type():
    return "proxy"

def get_info():
    return {"version"   : get_version()}

def get_encodings():
    return ["proxy"]

def init_module():
    #nothing to do!
    pass


class Encoder(object):
    """
        This is a "fake" encoder which just forwards
        the raw pixels and the metadata that goes with it.
    """

    def init_context(self, width, height, src_format, encoding, quality, speed, scaling, options):
        self.encoding = encoding
        self.width = width
        self.height = height
        self.quality = quality
        self.speed = speed
        self.scaling = scaling
        self.src_format = src_format
        self.last_frame_times = maxdeque(200)
        self.frames = 0
        self.time = 0

    def get_info(self):             #@DuplicatedSignature
        info = get_info()
        if self.src_format is None:
            return info
        info.update({"frames"    : self.frames,
                     "width"     : self.width,
                     "height"    : self.height,
                     "speed"     : self.speed,
                     "quality"   : self.quality,
                     "encoding"  : self.encoding,
                     "src_format": self.src_format,
                     "version"   : get_version()})
        if self.scaling!=(1,1):
            info["scaling"] = self.scaling
        #calculate fps:
        now = time.time()
        last_time = now
        cut_off = now-10.0
        f = 0
        for v in list(self.last_frame_times):
            if v>cut_off:
                f += 1
                last_time = min(last_time, v)
        if f>0 and last_time<now:
            info["fps"] = int(f/(now-last_time))
        return info

    def __str__(self):
        if self.src_format is None:
            return "proxy_encoder(uninitialized)"
        return "proxy_encoder(%s - %sx%s)" % (self.src_format, self.width, self.height)

    def is_closed(self):
        return self.src_format is None

    def get_encoding(self):
        return self.encoding

    def get_width(self):
        return self.width

    def get_height(self):
        return self.height

    def get_type(self):                     #@DuplicatedSignature
        return  "proxy"

    def get_src_format(self):
        return self.src_format

    def clean(self):                        #@DuplicatedSignature
        self.width = 0
        self.height = 0
        self.quality = 0
        self.speed = 0
        self.src_format = None

    def get_client_options(self, image, options):
        options = {
                "proxy"     : True,
                "frame"     : self.frames,
                #pass-through encoder options:
                "options"   : options,
                #redundant metadata:
                #"width"     : image.get_width(),
                #"height"    : image.get_height(),
                "quality"   : options.get("quality", self.quality),
                "speed"     : options.get("speed", self.speed),
                "rowstride" : image.get_rowstride(),
                "depth"     : image.get_depth(),
                "rgb_format": image.get_pixel_format(),
                }
        if self.scaling!=(1,1):
            options["scaling"] = self.scaling
        return options

    def compress_image(self, image, options={}):
        debug("compress_image(%s, %s)", image, options)
        #pass the pixels as they are
        assert image.get_planes()==ImageWrapper.PACKED, "invalid number of planes: %s" % image.get_planes()
        pixels = str(image.get_pixels())
        self.frames += 1
        self.last_frame_times.append(time.time())
        client_options = self.get_client_options(image, options)
        debug("compress_image(%s, %s) returning %s bytes and options=%s", image, options, len(pixels), client_options)
        return  pixels, client_options

    def set_encoding_speed(self, pct):
        self.speed = int(min(100, max(0, pct)))

    def set_encoding_quality(self, pct):
        self.quality = int(min(100, max(0, pct)))
