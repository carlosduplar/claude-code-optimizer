"""
Task queue processor with bugs and TODOs.
Handles async job scheduling and execution.
"""

import json
import time
import uuid
from typing import Dict, List, Optional, Callable, Any
from dataclasses import dataclass, asdict
from enum import Enum
from threading import Thread, Lock
from queue import Queue, Empty


class JobStatus(Enum):
    PENDING = 'pending'
    RUNNING = 'running'
    COMPLETED = 'completed'
    FAILED = 'failed'
    RETRYING = 'retrying'


@dataclass
class Job:
    """Represents a unit of work."""
    id: str
    task_name: str
    payload: Dict[str, Any]
    status: str = 'pending'
    priority: int = 5
    retries: int = 0
    max_retries: int = 3
    created_at: float = 0.0
    started_at: Optional[float] = None
    completed_at: Optional[float] = None
    error_message: Optional[str] = None

    def __post_init__(self):
        if self.created_at == 0.0:
            self.created_at = time.time()


class TaskRegistry:
    """Registry of available tasks."""

    def __init__(self):
        self._tasks: Dict[str, Callable] = {}

    def register(self, name: str, func: Callable) -> None:
        """Register a task handler."""
        self._tasks[name] = func

    def get(self, name: str) -> Optional[Callable]:
        """Get task handler by name."""
        return self._tasks.get(name)

    def list_tasks(self) -> List[str]:
        """List all registered tasks."""
        return list(self._tasks.keys())


class JobStore:
    """In-memory job storage."""

    def __init__(self):
        self._jobs: Dict[str, Job] = {}
        self._queue: Queue = Queue()
        self._lock = Lock()

    def add(self, job: Job) -> None:
        """Add job to store and queue."""
        with self._lock:
            self._jobs[job.id] = job

        # Queue by priority (lower number = higher priority)
        # BUG: Not actually using priority queue, just regular FIFO
        self._queue.put((job.priority, job.id))

    def get_next(self, timeout: float = 1.0) -> Optional[Job]:
        """Get next job from queue."""
        try:
            _, job_id = self._queue.get(timeout=timeout)
            return self._jobs.get(job_id)
        except Empty:
            return None

    def update(self, job: Job) -> None:
        """Update job in store."""
        with self._lock:
            self._jobs[job.id] = job

    def get(self, job_id: str) -> Optional[Job]:
        """Get job by ID."""
        return self._jobs.get(job_id)

    def get_by_status(self, status: str) -> List[Job]:
        """Get all jobs with given status."""
        return [j for j in self._jobs.values() if j.status == status]

    def stats(self) -> Dict[str, int]:
        """Get job statistics."""
        stats = {}
        for job in self._jobs.values():
            stats[job.status] = stats.get(job.status, 0) + 1
        return stats


class Worker(Thread):
    """Worker thread that processes jobs."""

    def __init__(self, store: JobStore, registry: TaskRegistry, worker_id: int):
        super().__init__(daemon=True)
        self.store = store
        self.registry = registry
        self.worker_id = worker_id
        self.running = True

    def run(self) -> None:
        """Main worker loop."""
        while self.running:
            job = self.store.get_next(timeout=1.0)

            if not job:
                continue

            self._process_job(job)

    def _process_job(self, job: Job) -> None:
        """Execute a single job."""
        job.status = 'running'
        job.started_at = time.time()
        self.store.update(job)

        handler = self.registry.get(job.task_name)

        if not handler:
            job.status = 'failed'
            job.error_message = f"Unknown task: {job.task_name}"
            job.completed_at = time.time()
            self.store.update(job)
            return

        try:
            result = handler(**job.payload)
            job.status = 'completed'
            job.completed_at = time.time()
            # TODO: Store result somewhere

        except Exception as e:
            job.retries += 1

            if job.retries < job.max_retries:
                job.status = 'retrying'
                # BUG: Not actually re-queueing the job
                job.error_message = str(e)
            else:
                job.status = 'failed'
                job.error_message = str(e)
                job.completed_at = time.time()

        self.store.update(job)

    def stop(self) -> None:
        """Stop worker."""
        self.running = False


class TaskQueue:
    """Main task queue interface."""

    def __init__(self, num_workers: int = 2):
        self.store = JobStore()
        self.registry = TaskRegistry()
        self.workers: List[Worker] = []
        self.num_workers = num_workers
        self._started = False

    def start(self) -> None:
        """Start worker threads."""
        if self._started:
            return

        for i in range(self.num_workers):
            worker = Worker(self.store, self.registry, i)
            worker.start()
            self.workers.append(worker)

        self._started = True

    def stop(self) -> None:
        """Stop all workers."""
        for worker in self.workers:
            worker.stop()

        for worker in self.workers:
            worker.join(timeout=5.0)

        self._started = False

    def register_task(self, name: str, handler: Callable) -> None:
        """Register a task handler."""
        self.registry.register(name, handler)

    def enqueue(self, task_name: str, payload: Dict,
                priority: int = 5, max_retries: int = 3) -> str:
        """Add job to queue."""
        if not self._started:
            self.start()

        job = Job(
            id=str(uuid.uuid4()),
            task_name=task_name,
            payload=payload,
            priority=priority,
            max_retries=max_retries
        )

        self.store.add(job)
        return job.id

    def get_status(self, job_id: str) -> Optional[Dict]:
        """Get job status."""
        job = self.store.get(job_id)
        if not job:
            return None

        return {
            'id': job.id,
            'status': job.status,
            'retries': job.retries,
            'created_at': job.created_at,
            'started_at': job.started_at,
            'completed_at': job.completed_at,
            'error': job.error_message
        }

    def wait_for_completion(self, job_id: str, timeout: float = 30.0) -> bool:
        """Wait for job to complete."""
        start = time.time()

        while time.time() - start < timeout:
            status = self.get_status(job_id)
            if not status:
                return False

            if status['status'] in ('completed', 'failed'):
                return True

            time.sleep(0.1)

        return False

    def get_stats(self) -> Dict[str, int]:
        """Get queue statistics."""
        return self.store.stats()


# Example task handlers
def send_email(to: str, subject: str, body: str) -> bool:
    """Send email task."""
    # TODO: Integrate with actual email service
    print(f"Sending email to {to}: {subject}")
    return True


def process_image(image_path: str, operations: List[str]) -> str:
    """Process image task."""
    # BUG: No validation of image_path (directory traversal possible)
    print(f"Processing {image_path} with {operations}")
    return f"processed_{image_path}"


def generate_report(report_type: str, date_range: Dict) -> str:
    """Generate report task."""
    # TODO: Add report caching
    print(f"Generating {report_type} report")
    return "report.pdf"


def main():
    """Demo task queue."""
    queue = TaskQueue(num_workers=2)

    # Register tasks
    queue.register_task('send_email', send_email)
    queue.register_task('process_image', process_image)

    # Enqueue jobs
    job1 = queue.enqueue('send_email', {
        'to': 'user@example.com',
        'subject': 'Welcome',
        'body': 'Hello!'
    })

    job2 = queue.enqueue('process_image', {
        'image_path': '/path/to/image.jpg',
        'operations': ['resize', 'crop']
    }, priority=1)

    print(f"Enqueued jobs: {job1}, {job2}")

    # Wait for completion
    queue.wait_for_completion(job1)
    queue.wait_for_completion(job2)

    print(f"Stats: {queue.get_stats()}")

    queue.stop()
    return 0


if __name__ == '__main__':
    exit(main())
