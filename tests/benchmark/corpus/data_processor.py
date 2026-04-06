"""
Data processing module with bugs and TODOs.
Handles CSV parsing, transformation, and validation.
"""

import csv
import json
from datetime import datetime
from typing import Dict, List, Optional, Any


class DataProcessor:
    """Process data files with various transformations."""

    def __init__(self, config: Dict[str, Any]):
        self.config = config
        self.errors: List[str] = []
        self.processed_count = 0

    def load_csv(self, filepath: str) -> List[Dict[str, str]]:
        """Load CSV file into list of dictionaries."""
        results = []
        try:
            with open(filepath, 'r') as f:
                reader = csv.DictReader(f)
                for row in reader:
                    results.append(row)
        except FileNotFoundError:
            self.errors.append(f"File not found: {filepath}")
            return []
        return results

    def validate_record(self, record: Dict[str, str]) -> bool:
        """Validate a single record has required fields."""
        required = self.config.get('required_fields', [])
        for field in required:
            if field not in record or not record[field]:
                return False
        return True

    def transform_date(self, date_str: str, fmt: str = "%Y-%m-%d") -> Optional[str]:
        """Transform date string to ISO format."""
        # TODO: Add timezone support
        try:
            dt = datetime.strptime(date_str, fmt)
            return dt.isoformat()
        except ValueError:
            return None

    def filter_by_value(self, records: List[Dict], field: str, min_val: float) -> List[Dict]:
        """Filter records where field exceeds minimum value."""
        filtered = []
        for record in records:
            try:
                val = float(record.get(field, 0))
                if val >= min_val:
                    filtered.append(record)
            except (ValueError, TypeError):
                # BUG: silently skipping bad values instead of logging
                continue
        return filtered

    def aggregate_by_key(self, records: List[Dict], key_field: str, val_field: str) -> Dict[str, float]:
        """Aggregate numeric values by key field."""
        aggregates: Dict[str, float] = {}
        counts: Dict[str, int] = {}

        for record in records:
            key = record.get(key_field)
            if not key:
                continue

            try:
                val = float(record.get(val_field, 0))
            except (ValueError, TypeError):
                val = 0.0

            aggregates[key] = aggregates.get(key, 0) + val
            counts[key] = counts.get(key, 0) + 1

        # TODO: Support multiple aggregation types (avg, max, min)
        return aggregates

    def export_json(self, records: List[Dict], filepath: str) -> bool:
        """Export records to JSON file."""
        try:
            with open(filepath, 'w') as f:
                json.dump(records, f, indent=2)
            return True
        except Exception as e:
            self.errors.append(f"Export failed: {e}")
            return False

    def process_pipeline(self, input_file: str, output_file: str) -> bool:
        """Run full processing pipeline."""
        records = self.load_csv(input_file)
        if not records:
            return False

        valid_records = []
        for record in records:
            if self.validate_record(record):
                # BUG: Not handling date transformation errors
                if 'date' in record:
                    record['date_iso'] = self.transform_date(record['date'])
                valid_records.append(record)

        min_val = self.config.get('min_value', 0)
        if min_val > 0:
            valid_records = self.filter_by_value(valid_records, 'amount', min_val)

        self.processed_count = len(valid_records)

        # TODO: Add validation summary report
        return self.export_json(valid_records, output_file)

    def deduplicate_records(self, records: List[Dict], key_field: str) -> List[Dict]:
        """Remove duplicate records based on key field."""
        seen = set()
        unique = []
        for record in records:
            key = record.get(key_field)
            if key and key not in seen:
                seen.add(key)
                unique.append(record)
        return unique

    def normalize_field_names(self, record: Dict[str, str]) -> Dict[str, str]:
        """Normalize field names to lowercase with underscores."""
        normalized = {}
        for key, value in record.items():
            # BUG: Not handling None keys
            new_key = key.lower().replace(' ', '_').replace('-', '_')
            normalized[new_key] = value
        return normalized

    def calculate_statistics(self, records: List[Dict], field: str) -> Dict[str, float]:
        """Calculate min, max, mean, median for numeric field."""
        values = []
        for record in records:
            try:
                val = float(record.get(field, 0))
                values.append(val)
            except (ValueError, TypeError):
                # TODO: Track invalid values
                continue

        if not values:
            return {}

        values.sort()
        n = len(values)

        # BUG: Integer division in Python 2 style (if ported)
        median = values[n // 2] if n % 2 else (values[n // 2 - 1] + values[n // 2]) / 2

        return {
            'count': n,
            'min': values[0],
            'max': values[-1],
            'mean': sum(values) / n,
            'median': median
        }

    def merge_datasets(self, left: List[Dict], right: List[Dict],
                       left_key: str, right_key: str) -> List[Dict]:
        """Perform left join on two datasets."""
        # Build index
        right_index = {}
        for record in right:
            key = record.get(right_key)
            if key:
                right_index[key] = record

        merged = []
        for left_record in left:
            key = left_record.get(left_key)
            match = right_index.get(key, {})
            # BUG: Modifying left record directly
            left_record.update(match)
            merged.append(left_record)

        return merged


def load_config_from_env() -> Dict[str, Any]:
    """Load processor config from environment variables."""
    import os

    config = {
        'required_fields': os.getenv('REQUIRED_FIELDS', 'id,name').split(','),
        'min_value': float(os.getenv('MIN_VALUE', '0')),
        'date_format': os.getenv('DATE_FORMAT', '%Y-%m-%d'),
        'output_encoding': os.getenv('OUTPUT_ENCODING', 'utf-8'),
    }

    # TODO: Add file-based config override
    return config


def batch_process_files(processor: DataProcessor, files: List[str],
                         output_dir: str) -> Dict[str, int]:
    """Process multiple files and return statistics."""
    stats = {'success': 0, 'failed': 0, 'total_records': 0}

    for filepath in files:
        filename = filepath.split('/')[-1].replace('.csv', '.json')
        output_path = f"{output_dir}/{filename}"

        # BUG: Not validating output_dir exists
        if processor.process_pipeline(filepath, output_path):
            stats['success'] += 1
            stats['total_records'] += processor.processed_count
        else:
            stats['failed'] += 1

    return stats


def main():
    """CLI entry point."""
    config = {
        'required_fields': ['id', 'name', 'amount'],
        'min_value': 100.0
    }

    processor = DataProcessor(config)
    success = processor.process_pipeline('input.csv', 'output.json')

    if success:
        print(f"Processed {processor.processed_count} records")
    else:
        print(f"Errors: {processor.errors}")

    return 0 if success else 1


if __name__ == '__main__':
    exit(main())
