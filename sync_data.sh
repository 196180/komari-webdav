#!/bin/sh
VENV_PYTHON="/app/venv/bin/python"
if [ -z "$WEBDAV_URL" ] || [ -z "$WEBDAV_USERNAME" ] || [ -z "$WEBDAV_PASSWORD" ]; then
    echo "Starting without sync functionality - missing WEBDAV_URL, WEBDAV_USERNAME, or WEBDAV_PASSWORD"
    exit 0
fi
WEBDAV_BACKUP_PATH=${WEBDAV_BACKUP_PATH:-""}
FULL_WEBDAV_URL="${WEBDAV_URL}"
if [ -n "$WEBDAV_BACKUP_PATH" ]; then
    FULL_WEBDAV_URL="${WEBDAV_URL}/${WEBDAV_BACKUP_PATH}"
fi
restore_backup() {
    echo "开始从 WebDAV 下载最新备份..."
    $VENV_PYTHON -c "
import sys
import os
import tarfile
import requests
import shutil
import subprocess
from webdav3.client import Client
options = {
    'webdav_hostname': '${FULL_WEBDAV_URL}',
    'webdav_login': '${WEBDAV_USERNAME}',
    'webdav_password': '${WEBDAV_PASSWORD}'
}
client = Client(options)
try:
    backups = [file for file in client.list() if file.endswith('.tar.gz') and file.startswith('komari_backup_')]
except Exception as e:
    print(f'连接 WebDAV 服务器出错: {e}')
    sys.exit(1)
if not backups:
    print('没有找到备份文件，跳过恢复步骤。')
    sys.exit(0)
latest_backup = sorted(backups)[-1]
print(f'最新备份文件：{latest_backup}')
try:
    with requests.get(f'${FULL_WEBDAV_URL}/{latest_backup}', auth=('${WEBDAV_USERNAME}', '${WEBDAV_PASSWORD}'), stream=True) as r:
        if r.status_code == 200:
            with open(f'/tmp/{latest_backup}', 'wb') as f:
                for chunk in r.iter_content(chunk_size=8192):
                    f.write(chunk)
            print(f'成功下载备份文件到 /tmp/{latest_backup}')
            # 检查数据库文件是否被占用
            try:
                pids = subprocess.check_output(['lsof', '-t', '/app/data/komari.db']).decode().strip()
                if pids:
                    print('数据库文件被占用，无法恢复备份。')
                    sys.exit(1)
            except subprocess.CalledProcessError:
                pass
            # 解压目录
            with tarfile.open(f'/tmp/{latest_backup}', 'r:gz') as tar:
                tar.extractall('/app/')
            print(f'成功从 {latest_backup} 恢复备份到 /app/data')
        else:
            print(f'下载备份失败：{r.status_code}')
except Exception as e:
    print(f'恢复备份过程中出错: {e}')
"
}
echo "Downloading latest backup from WebDAV..."
restore_backup
sync_data() {
    while true; do
        echo "Starting sync process at $(date)"
        timestamp=$(date +%Y%m%d_%H%M%S)
        backup_file="komari_backup_${timestamp}.tar.gz"
        # 备份/app/data目录
        cd /app
        tar -czf "/tmp/${backup_file}" data
        curl -u "$WEBDAV_USERNAME:$WEBDAV_PASSWORD" -T "/tmp/${backup_file}" "$FULL_WEBDAV_URL/${backup_file}"
        if [ $? -eq 0 ]; then
            echo "Successfully uploaded ${backup_file} to WebDAV"
        else
            echo "Failed to upload ${backup_file} to WebDAV"
        fi
        $VENV_PYTHON -c "
from webdav3.client import Client
options = {
    'webdav_hostname': '${FULL_WEBDAV_URL}',
    'webdav_login': '${WEBDAV_USERNAME}',
    'webdav_password': '${WEBDAV_PASSWORD}'
}
client = Client(options)
backups = [file for file in client.list() if file.endswith('.tar.gz') and file.startswith('komari_backup_')]
backups.sort()
if len(backups) > 5:
    to_delete = len(backups) - 5
    for file in backups[:to_delete]:
        client.clean(file)
        print(f'Successfully deleted {file}.')
else:
    print('Only {} backups found, no need to clean.'.format(len(backups)))
" 2>&1
        rm -f "/tmp/${backup_file}"
        SYNC_INTERVAL=${SYNC_INTERVAL:-600}
        echo "Next sync in ${SYNC_INTERVAL} seconds..."
        sleep $SYNC_INTERVAL
    done
}
sync_data &
