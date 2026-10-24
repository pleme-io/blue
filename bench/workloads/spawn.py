import asyncio


async def worker(q, i):
    await q.put(i)


async def main():
    q = asyncio.Queue()
    await asyncio.gather(*(worker(q, i) for i in range(10000)))
    print(sum([q.get_nowait() for _ in range(10000)]))

asyncio.run(main())
