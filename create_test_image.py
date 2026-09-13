"""Создаёт тестовое изображение с текстом и формулой для проверки OCR"""
from PIL import Image, ImageDraw, ImageFont

# Создаём белое изображение
img = Image.new("RGB", (800, 400), "white")
draw = ImageDraw.Draw(img)

# Пытаемся загрузить шрифт, если не получится — используем стандартный
try:
    font = ImageFont.truetype("arial.ttf", 32)
    font_small = ImageFont.truetype("arial.ttf", 24)
except:
    font = ImageFont.load_default()
    font_small = font

# Пишем текст
draw.text((30, 30), "Лекция по математике", fill="black", font=font)
draw.text((30, 90), "Определение: функция f(x) называется", fill="black", font=font_small)
draw.text((30, 130), "непрерывной в точке x0, если предел", fill="black", font=font_small)
draw.text((30, 170), "lim f(x) = f(x0)", fill="black", font=font)
draw.text((30, 230), "Пример: y = x^2 + 3x - 5", fill="black", font=font)
draw.text((30, 290), "Интеграл: S = a/b * sqrt(x)", fill="black", font=font)
draw.text((30, 340), "Сумма от i=1 до n", fill="black", font=font_small)

img.save("test_lecture.jpg", quality=95)
print("Тестовое изображение сохранено: test_lecture.jpg")