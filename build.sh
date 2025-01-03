export ROOT=`cd ../../../ && pwd`
export target=RedisBloom
export ROOT_SCRIPT=$ROOT/script/multi-benches/$target
# Đường dẫn đến thư mục RedisBloom
#REPO_PATH=$ROOT_SCRIPT
#REDISBLOOM_PATH="$ROOT_SCRIPT/Redis/RedisBloom"
#REDIS_CONF="$REPO_PATH/Redis/redis-stable/redis.conf"
REPO_PATH=$ROOT_SCRIPT
REDISBLOOM_PATH="$ROOT_SCRIPT/RedisBloom"
REDIS_CONF="$REPO_PATH/drivers/cuckoo/redis-stable/redis.conf"
function collect_branchs ()
{
	ALL_BRANCHS=`find $ROOT/$target -name branch_vars.bv`
	
	if [ -f "$ROOT_SCRIPT/drivers/branch_vars.bv" ]; then
		rm $ROOT_SCRIPT/drivers/branch_vars.bv
	fi
	
	echo "@@@@@@@@@ ALL_BRANCHES -----> $ALL_BRANCHS"
	for branch in $ALL_BRANCHS
	do
		cat $branch >> $ROOT_SCRIPT/drivers/branch_vars.bv
		rm $branch
	done
}

function compile ()
{
	if [ -d "$ROOT/$target" ]; then
        rm -rf RedisBloom
    fi

    git clone --recursive https://github.com/RedisBloom/RedisBloom.git -b v2.6.8
	
	pushd $target
	
	export CC="afl-cc -lxFuzztrace"
	export CXX="afl-c++"
	
	cp $ROOT_SCRIPT/system-setup.py $ROOT/$target/sbin/
    ./sbin/setup
	#bash -l #không thể sử dụng trong script vì sẽ mở một login shell và sẽ tạm dừng script --> không chạy tiếp
	bash -l -c "make && exit"
	make
	# Chuyển đến thư mục RedisBloom và chạy make run -n
	# cd "$REDISBLOOM_PATH" || { echo "Error: Cannot access RedisBloom directory"; exit 1; }
	# Trích xuất đường dẫn module từ lệnh make run -n
	MODULE_PATH=$(make run -n | grep -- '--' | awk '{print $2 $3}' | sed 's/^--loadmodule/loadmodule /')

	if [[ -z "$MODULE_PATH" ]]; then
		echo "Error: Unable to extract module path."
		exit 1
	fi

	echo "Module path extracted: $MODULE_PATH"

	# Kiểm tra xem module đã tồn tại trong tệp cấu hình chưa
	if grep -q "$MODULE_PATH" "$REDIS_CONF"; then
		echo "Module already exists in redis.conf. No changes made."
	else
		# Kiểm tra xem phần MODULES có tồn tại trong redis.conf không
		if grep -q "################################## MODULES #####################################" "$REDIS_CONF"; then
			# Thêm dòng loadmodule sau phần MODULES
			awk -v module="$MODULE_PATH" '
					/################################## MODULES #####################################/ {
						print; getline; print; print module; next
				}
				{ print }
			' "$REDIS_CONF" > "$REDIS_CONF.tmp"  && mv "$REDIS_CONF.tmp" "$REDIS_CONF"
			echo "Added loadmodule to MODULES section in redis.conf"
		else
			echo "Error: MODULES section not found in redis.conf"
			exit 1
		fi
	fi
	echo "Setup redis.conf complete."
	popd
}

#Pyversion=`PyVersion.sh` #tìm tên thư viện bằng lệnh python -m site và vào thư mục site-packages kiểm tra.
#if [ -d "$Pyversion/site-packages/redis" ]; then 
	#rm -rf $Pyversion/site-packages/redis*
#fi

# 1. compile the C unit
cd $ROOT
compile

# 2. summarize the Python unit
cd $ROOT/$target
PyDir=tests/flow
python -m parser $PyDir  > python.log
cp $PyDir/py_summary.xml $ROOT_SCRIPT/

collect_branchs
cd $ROOT
