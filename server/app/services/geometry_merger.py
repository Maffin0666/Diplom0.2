from typing import List, Dict, Any


class BoundingBoxMerger:
    """Безопасное слияние только компактных многоэтажных математических формул (дробей)."""

    @classmethod
    def merge_math_regions(cls, boxes: List[Dict[str, Any]], image_shape: tuple) -> List[Dict[str, Any]]:
        if not boxes:
            return []

        h_img, w_img = image_shape[:2]
        sorted_boxes = sorted(boxes, key=lambda b: b['box'][1])

        merged = []
        used = [False] * len(sorted_boxes)

        for i in range(len(sorted_boxes)):
            if used[i]:
                continue

            cur_box = list(sorted_boxes[i]['box'])
            raw_text = sorted_boxes[i].get('raw', {}).get('text', '')
            w_cur = cur_box[2] - cur_box[0]

            # Если блок широкий (строка конспекта) или содержит много слов — это обычная строка текста
            is_full_line = (w_cur > w_img * 0.40) or (len(raw_text.split()) > 3)

            is_math_cluster = False

            if not is_full_line:
                for j in range(i + 1, len(sorted_boxes)):
                    if used[j]:
                        continue

                    cand_box = sorted_boxes[j]['box']
                    w_cand = cand_box[2] - cand_box[0]

                    # Кандидат на объединение в дробь тоже должен быть компактным
                    if w_cand > w_img * 0.40:
                        continue

                    # Вычисляем горизонтальное перекрытие
                    inter_min = max(cur_box[0], cand_box[0])
                    inter_max = min(cur_box[2], cand_box[2])
                    intersection = max(0, inter_max - inter_min)
                    union = (cur_box[2] - cur_box[0]) + (cand_box[2] - cand_box[0]) - intersection
                    h_iou = intersection / float(union) if union > 0 else 0.0

                    vertical_gap = cand_box[1] - cur_box[3]
                    avg_h = ((cur_box[3] - cur_box[1]) + (cand_box[3] - cand_box[1])) / 2.0

                    # Склеиваем только компактные вертикальные структуры
                    if h_iou > 0.65 and 0 <= vertical_gap <= (avg_h * 0.8):
                        cur_box[0] = min(cur_box[0], cand_box[0])
                        cur_box[1] = min(cur_box[1], cand_box[1])
                        cur_box[2] = max(cur_box[2], cand_box[2])
                        cur_box[3] = max(cur_box[3], cand_box[3])
                        used[j] = True
                        is_math_cluster = True

            merged.append({
                'box': cur_box,
                'is_formula_candidate': is_math_cluster,
                'original_raw': sorted_boxes[i].get('raw', {})
            })
            used[i] = True

        return merged