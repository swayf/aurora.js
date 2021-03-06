class M4ADemuxer extends Demuxer
    Demuxer.register(M4ADemuxer)
    
    @probe: (buffer) ->
        return buffer.peekString(8, 4) is 'M4A '
        
    # from http://atomicparsley.sourceforge.net/mpeg-4files.html
    metafields = 
        '©alb': 'Album'
        '©arg': 'Arranger'
        '©art': 'Artist'
        '©ART': 'Album Artist'
        'catg': 'Category'
        '©com': 'Composer'
        'covr': 'Cover Art'
        'cpil': 'Compilation'
        '©cpy': 'Copyright'
        'cprt': 'Copyright'
        'desc': 'Description'
        'disk': 'Disk Number'
        '©gen': 'Genre' # custom genres
        'gnre': 'Genre' # standard ones
        '©grp': 'Grouping'
        '©isr': 'ISRC Code'
        'keyw': 'Keyword'
        '©lab': 'Record Label'
        '©lyr': 'Lyrics'
        '©nam': 'Title'
        'pcst': 'Podcast'
        'pgap': 'Gapless'
        '©phg': 'Recording Copyright'
        '©prd': 'Producer'
        '©prf': 'Performers'
        'purl': 'Podcast URL'
        'rtng': 'Rating'
        '©swf': 'Songwriter'
        'tmpo': 'Tempo'
        '©too': 'Encoder'
        'trkn': 'Track Number'
        '©wrt': 'Composer'
        
    genres = [
        "Blues", "Classic Rock", "Country", "Dance", "Disco",
        "Funk", "Grunge", "Hip-Hop", "Jazz", "Metal",
        "New Age", "Oldies", "Other", "Pop", "R&B",
        "Rap", "Reggae", "Rock", "Techno", "Industrial",
        "Alternative", "Ska", "Death Metal", "Pranks", "Soundtrack",
        "Euro-Techno", "Ambient", "Trip-Hop", "Vocal", "Jazz+Funk",
        "Fusion", "Trance", "Classical", "Instrumental", "Acid",
        "House", "Game", "Sound Clip", "Gospel", "Noise",
        "AlternRock", "Bass", "Soul", "Punk", "Space", 
        "Meditative", "Instrumental Pop", "Instrumental Rock", "Ethnic", "Gothic", 
        "Darkwave", "Techno-Industrial", "Electronic", "Pop-Folk", "Eurodance", 
        "Dream", "Southern Rock", "Comedy", "Cult", "Gangsta",
        "Top 40", "Christian Rap", "Pop/Funk", "Jungle", "Native American",
        "Cabaret", "New Wave", "Psychadelic", "Rave", "Showtunes",
        "Trailer", "Lo-Fi", "Tribal", "Acid Punk", "Acid Jazz",
        "Polka", "Retro", "Musical", "Rock & Roll", "Hard Rock",
        "Folk", "Folk/Rock", "National Folk", "Swing", "Fast Fusion",
        "Bebob", "Latin", "Revival", "Celtic", "Bluegrass",
        "Avantgarde", "Gothic Rock", "Progressive Rock", "Psychedelic Rock", "Symphonic Rock",
        "Slow Rock", "Big Band", "Chorus", "Easy Listening", "Acoustic", 
        "Humour", "Speech", "Chanson", "Opera", "Chamber Music", "Sonata", 
        "Symphony", "Booty Bass", "Primus", "Porn Groove", 
        "Satire", "Slow Jam", "Club", "Tango", "Samba", 
        "Folklore", "Ballad", "Power Ballad", "Rhythmic Soul", "Freestyle", 
        "Duet", "Punk Rock", "Drum Solo", "A Capella", "Euro-House",
        "Dance Hall"
    ]
    
    readChunk: ->
        while @stream.available(1)
            if not @readHeaders and @stream.available(8)
                @len = @stream.readUInt32() - 8
                @type = @stream.readString(4)
                
                continue if @len is 0
                @readHeaders = true
                
            if @type of metafields
                @metafield = @type
                @readHeaders = false
                continue
                
            switch @type
                when 'ftyp'
                    return unless @stream.available(@len)
                
                    if @stream.readString(4) isnt 'M4A '
                        return @emit 'error', 'Not a valid M4A file.'
                    
                    @stream.advance(@len - 4)
            
                when 'moov', 'trak', 'mdia', 'minf', 'stbl', 'udta', 'ilst'
                    # traverse into these types - they are container atoms
                    break
                    
                when 'stco' # TODO: 'co64' for 64 bit version...
                    @stream.advance(4) # version and flags
                    
                    entryCount = @stream.readUInt32()
                    @chunkOffsets = []
                    
                    for i in [0...entryCount]
                        @chunkOffsets[i] = @stream.readUInt32()
            
                when 'meta'
                    @metadata = {}
                    @metaMaxPos = @stream.offset + @len
                    
                    @stream.advance(4) # random zeros
                    
                when 'data'
                    return unless @stream.available(@len)
                    
                    field = metafields[@metafield]
                    switch @metafield
                        when 'disk', 'trkn'
                            pos = @stream.offset
                            @stream.advance(10)

                            @metadata[field] = @stream.readUInt16() + ' of ' + @stream.readUInt16()
                            @stream.advance(@len - (@stream.offset - pos))

                        when 'cpil', 'pgap', 'pcst'
                            @stream.advance(8)
                            @metadata[field] = @stream.readUInt8() is 1

                        when 'gnre'
                            @stream.advance(8)
                            @metadata[field] = genres[@stream.readUInt16() - 1]

                        when 'rtng'
                            @stream.advance(8)
                            rating = @stream.readUInt8()
                            @metadata[field] = if rating == 2 then 'Clean' else if rating != 0 then 'Explicit' else 'None'

                        when 'tmpo'
                            @stream.advance(8)
                            @metadata[field] = @stream.readUInt16()

                        when 'covr'
                            @stream.advance(8)
                            @metadata[field] = @stream.readBuffer(@len - 8)

                        else
                            @metadata[field] = @stream.readUTF8(@len)
                            
                when 'mdhd'
                    return unless @stream.available(@len)
                    
                    @stream.advance(4) # version and flags
                    @stream.advance(8) # creation and modification dates
                    
                    sampleRate = @stream.readUInt32()
                    duration = @stream.readUInt32()
                    @emit 'duration', duration / sampleRate * 1000 | 0
                    
                    @stream.advance(4) # language and quality
                    
                when 'stsd'
                    return unless @stream.available(@len)
                    @stream.advance(4) # version and flags
                    
                    numEntries = @stream.readUInt32()
                    if numEntries isnt 1
                        return @emit 'error', "Only expecting one entry in sample description atom!"
                        
                    @stream.advance(4) # size
                    
                    @format = {}
                    @format.formatID = @stream.readString(4)
                    
                    @stream.advance(6) # reserved
                    
                    if @stream.readUInt16() isnt 1
                        return @emit 'error', 'Unknown version in stsd atom.'
                    
                    @stream.advance(6) # skip revision level and vendor
                    @stream.advance(2) # reserved
                    
                    @format.channelsPerFrame = @stream.readUInt16()
                    @format.bitsPerChannel = @stream.readUInt16()
                    
                    @stream.advance(4) # skip compression id and packet size
                    
                    @format.sampleRate = @stream.readUInt16()
                    @stream.advance(2)
                    
                    @emit 'format', @format
                    
                when 'alac'
                    @stream.advance(4)
                    @emit 'cookie', @stream.readBuffer(@len - 4)
                    @sentCookie = true
                    @sendDataSections() if @dataSections
                    
                when 'esds'
                    @readEsds()
                    @sentCookie = true
                    @sendDataSections() if @dataSections
                    
                when 'mdat'
                    if @chunkOffsets and @stream.offset < @chunkOffsets[0]
                        diff = @chunkOffsets[0] - @stream.offset
                        @stream.advance(diff)
                        @len -= diff
                                        
                    buffer = @stream.readSingleBuffer(@len)
                    @len -= buffer.length
                    @readHeaders = @len > 0

                    if @sentCookie
                        @emit 'data', buffer, @len is 0
                    else
                        @dataSections ?= []
                        @dataSections.push buffer
                    
                else
                    return unless @stream.available(@len)
                    @stream.advance(@len)
            
            # emit the metadata when all of it has been read        
            if @stream.offset is @metaMaxPos
                @emit 'metadata', @metadata
                
            @readHeaders = false unless @type is 'mdat'
        
        return
        
    sendDataSections: ->
        interval = setInterval =>
            @emit 'data', @dataSections.shift(), @dataSections.length is 0
            clearInterval interval if @dataSections.length is 0
        , 100
        
    @readDescrLen: (stream) ->
        len = 0
        count = 4
        
        while count--
            c = stream.readUInt8()
            len = (len << 7) | (c & 0x7f)
            break unless c & 0x80
            
        return len
        
    readDescr = (stream) ->
        tag = stream.readUInt8();
        return [tag, M4ADemuxer.readDescrLen(stream)]
        
    readEsds: ->
        startPos = @stream.offset
        @stream.advance(4) # version and flags
        [tag, len] = readDescr @stream
        
        if tag is 0x03 # MP4ESDescrTag
            @stream.advance(2) # id
            flags = @stream.readUInt8()
            
            if flags & 0x80 # streamDependenceFlag
                @stream.advance(2)
                
            if flags & 0x40 # URL_Flag
                @stream.advance @stream.readUInt8()
                
            if flags & 0x20 # OCRstreamFlag
                @stream.advance(2)
                
        else
            @stream.advance(2) # id
            
        [tag, len] = readDescr @stream
        if tag is 0x04 # MP4DecConfigDescrTag
            codec_id = @stream.readUInt8() # might want this... (isom.c:35)
            @stream.advance(1) # stream type
            @stream.advance(3) # buffer size
            @stream.advance(4) # max bitrate
            @stream.advance(4) # avg bitrate
            
            [tag, len] = readDescr @stream
            if tag is 0x05 # MP4DecSpecificDescrTag
                @emit 'cookie', @stream.readBuffer(len)
        
        # skip garbage at the end        
        extra = @len - @stream.offset + startPos
        @stream.advance(extra)