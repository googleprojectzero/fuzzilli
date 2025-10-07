import asyncio, os, time
from redis.asyncio import Redis
import asyncpg

GROUP = os.getenv("GROUP", "g_fuzz")
CONSUMER = os.getenv("CONSUMER", "c_sync_1")
STREAMS = os.getenv("STREAMS", "redis1=redis://redis1:6379,redis2=redis://redis2:6379").split(",")
STREAM_NAME = "stream:fuzz:updates"
PG_DSN = os.getenv("PG_DSN", "postgres://fuzzuser:pass@pg:5432/main")

CREATE_GROUP_OK = {"OK", "BUSYGROUP Consumer Group name already exists"}

UPSERT_SQL = """
INSERT INTO fuzz_data (key, val, origin, vclock, updated_at)
VALUES ($1, $2, $3, $4, NOW())
ON CONFLICT (key) DO UPDATE SET
  val = CASE WHEN EXCLUDED.vclock >= fuzz_data.vclock THEN EXCLUDED.val ELSE fuzz_data.val END,
  origin = CASE WHEN EXCLUDED.vclock >= fuzz_data.vclock THEN EXCLUDED.origin ELSE fuzz_data.origin END,
  vclock = GREATEST(fuzz_data.vclock, EXCLUDED.vclock),
  updated_at = CASE WHEN EXCLUDED.vclock >= fuzz_data.vclock THEN NOW() ELSE fuzz_data.updated_at END;
"""

async def ensure_group(r: Redis, stream: str):
    try:
        await r.xgroup_create(stream, GROUP, id="$", mkstream=True)
    except Exception as e:
        if "BUSYGROUP" not in str(e):
            raise

async def consume_stream(label: str, redis_url: str, pg):
    r = Redis.from_url(redis_url)
    await ensure_group(r, STREAM_NAME)
    while True:
        try:
            # Read new messages for this consumer
            resp = await r.xreadgroup(GROUP, CONSUMER, {STREAM_NAME: ">"}, count=100, block=5000)
            if not resp:
                continue
            # resp = [(b'stream:fuzz:updates', [(id, {b'k':b'v', ...}), ...])]
            for _, entries in resp:
                for msg_id, data in entries:
                    op = data.get(b'op', b'').decode()
                    key = data.get(b'key', b'').decode()
                    origin = data.get(b'origin', b'').decode()
                    vclock = int(data.get(b'vclock', b'0').decode() or 0)
                    if op == "del":
                        # Represent deletes: write NULL / tombstone (optional)
                        await pg.execute(
                            "DELETE FROM fuzz_data WHERE key=$1 AND vclock <= $2", key, vclock
                        )
                    else:
                        val = data.get(b'val', b'')
                        await pg.execute(UPSERT_SQL, key, val, origin, vclock)
                    await r.xack(STREAM_NAME, GROUP, msg_id)
        except Exception as e:
            # backoff on errors
            await asyncio.sleep(1)

async def main():
    pg = await asyncpg.connect(PG_DSN)
    tasks = []
    for pair in STREAMS:
        label, url = pair.split("=")
        tasks.append(asyncio.create_task(consume_stream(label, url, pg)))
    await asyncio.gather(*tasks)

if __name__ == "__main__":
    asyncio.run(main())
