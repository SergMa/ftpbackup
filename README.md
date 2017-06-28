# ftpbackup
Shell script that makes recursive and incremtal backuping of files
from local machine to remote FTP-server. Is based on ncftpls and ncftpput
utilites. Written to be simple enough to work even in minimalistic shell
of Busybox. Script works even with FTP-servers, that do not support
Recursive mode in ncftpls.
