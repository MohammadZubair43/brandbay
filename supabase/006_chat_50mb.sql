-- BrandBay update 006: chat files can be up to 50 MB (the free plan's maximum).
update storage.buckets set file_size_limit = 52428800 where id = 'chat-files';
