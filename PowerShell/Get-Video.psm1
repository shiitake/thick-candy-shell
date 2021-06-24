Function Get-Video{
# Download video segments from website
# from https://www.codementor.io/@chuksdurugo/download-and-combine-media-segments-of-a-hls-stream-locally-using-ffmpeg-150zo6t775

param([string]$Url,$Program)	

# To view programs
ffmpeg -i $m3u2

# Downloads files and creates outlist
ffmpeg -i $Url -map p:6 -c copy -t 60 -f segment -segment_list out.list out%03d.ts



}