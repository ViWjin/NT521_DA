import subprocess
import os
import sys
import time
import signal
import re
import pyprob

pyprob.Setup('py_summary.xml', 'cuckoo.py')

def LoadTest(FileName):
    with open(FileName, 'rb') as fw:
        value = fw.read()
        return value
def terminate_redis_server(redis_process):
    if redis_process and redis_process.poll() is None:  # Nếu vẫn đang chạy
            redis_process.terminate()
            try:
               redis_process.wait(timeout=2)
            except subprocess.TimeoutExpired:
               redis_process.kill()
if __name__ == "__main__":
    try:
        value = LoadTest(sys.argv[1])
        parts = value.split(b' ')
        #print(parts, len(parts))
        if len(parts) != 2:
            raise ValueError("Input file must contain an iterator and data separated by a space")
        iterator = parts[0].decode() # Chuyển từ dạng byte sang chuỗi
        data = parts[1].strip()
        if b'\x00' in parts[0] or not re.search("[0-9]", iterator):
            #print("Invalid iterator")
            sys.exit(1)
        if b'\x00' in data:
            #print("Error: Data contains null bytes")
            sys.exit(1)
        print(iterator, data) 
        #data = data.decode()
        # Khởi động Redis server trong AFL++ môi trường
        redis_conf_path = os.path.abspath("../redis-stable/redis.conf")
        redis_process = subprocess.Popen(
            ["redis-server", redis_conf_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        # Chờ Redis server khởi động
        time.sleep(0.5)

        # Gửi lệnh Redis qua redis-cli
        try:
            subprocess.run(["redis-cli", "FLUSHALL"], check=True)
            subprocess.run(["redis-cli", "CF.RESERVE", "cf", "4"], check=True)
            subprocess.run(["redis-cli", "CF.LOADCHUNK", "cf", iterator, data], check=True)
        except subprocess.CalledProcessError as e:
            terminate_redis_server(redis_process)
            print(f"Command failed: {e.cmd}, return code: {e.returncode}")
        except ValueError as ve: # Lỗi embedded null bytes
            terminate_redis_server(redis_process) # Tắt server nếu lỗi
            print(f"Lỗi embedded null byte: {ve}")
            sys.exit(1)
        
        # Kiểm tra nếu Redis server crash
        if redis_process.poll() not in (None, 0):
            exit_code = redis_process.returncode
            print(f"Redis server crashed with exit code {exit_code}")
            if exit_code == -11:  # Chỉ định lỗi SIGSEGV
                os.kill(os.getpid(), signal.SIGSEGV)  # Gửi tín hiệu crash cho AFL++

        # Tắt server
        terminate_redis_server(redis_process)
    except Exception as e:
        print(e)
        pyprob.PyExcept (type(e).__name__, __file__, e.__traceback__.tb_lineno)
        #sys.exit(1)  # Đảm bảo exit với mã lỗi nếu có lỗi xảy ra
