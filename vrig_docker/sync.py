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
INSERT INTO program (program_base64, fuzzer_id, feedback_vector, turboshaft_ir, coverage_total, created_at)
VALUES ($1, $2, $3, $4, $5, NOW())
ON CONFLICT (program_base64) DO UPDATE SET
  feedback_vector = EXCLUDED.feedback_vector,
  turboshaft_ir = EXCLUDED.turboshaft_ir,
  coverage_total = EXCLUDED.coverage_total,
  created_at = NOW();
"""

UPDATE_FEEDBACK_SQL = """
UPDATE program SET feedback_vector = $2
WHERE program_base64 = $1;
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
                    program_base64 = data.get(b'program_base64', b'').decode()
                    
                    if op == "del":
                        # Delete program entry
                        await pg.execute(
                            "DELETE FROM program WHERE program_base64=$1", program_base64
                        )
                    elif op == "update_feedback":
                        # Update only the feedback_vector field
                        feedback_vector = data.get(b'feedback_vector', b'null').decode()
                        await pg.execute(UPDATE_FEEDBACK_SQL, program_base64, feedback_vector)
                    else:
                        # Full upsert (op == "set" or default)
                        fuzzer_id = int(data.get(b'fuzzer_id', b'0').decode() or 0)
                        feedback_vector = data.get(b'feedback_vector', b'null').decode()
                        turboshaft_ir = data.get(b'turboshaft_ir', b'').decode()
                        coverage_total = float(data.get(b'coverage_total', b'0').decode() or 0)
                        
                        await pg.execute(UPSERT_SQL, program_base64, fuzzer_id, feedback_vector, turboshaft_ir, coverage_total)
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
