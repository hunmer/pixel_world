from PIL import Image
import os

img = Image.open('C:/Users/Administrator/Documents/cursor_lps_anime_v2-pixel-424x424.png')
width, height = img.size

# 内容边界（从前面的检测）
x_min, x_max = 15, 407
y_min, y_max = 112, 310
content_width = x_max - x_min + 1
content_height = y_max - y_min + 1

# 计算每个格子的尺寸（3行7列）
cell_width = content_width / 7
cell_height = content_height / 3

# 创建输出目录
output_dir = 'E:/pixel_world/assets/ui/gen/split_anime'
os.makedirs(output_dir, exist_ok=True)

# 定义指针名称（按行列顺序）
cursor_names = [
    # 第1行
    'cursor_arrow_white', 'cursor_arrow_blue', 'cursor_arrow_gold', 'cursor_banned',
    'cursor_crosshair_white', 'cursor_crosshair_red', 'cursor_grab_white',
    # 第2行
    'cursor_hand_white', 'cursor_help', 'cursor_beam', 'cursor_link',
    'cursor_magic', 'cursor_move', 'cursor_paint',
    # 第3行
    'cursor_resize_h', 'cursor_resize_diag', 'cursor_resize_v', 'cursor_sword',
    'cursor_talk', 'cursor_target', 'cursor_grab_circle'
]

# 拆分并保存每个指针
for row in range(3):
    for col in range(7):
        # 计算当前格子的边界
        left = int(x_min + col * cell_width)
        upper = int(y_min + row * cell_height)
        right = int(x_min + (col + 1) * cell_width)
        lower = int(y_min + (row + 1) * cell_height)

        # 裁剪
        cell_img = img.crop((left, upper, right, lower))

        # 找到当前格子内的非透明内容并裁剪
        bbox = cell_img.getbbox()
        if bbox:
            cell_img = cell_img.crop(bbox)

        # 缩放到 32x32（保持比例）
        cell_img.thumbnail((32, 32), Image.Resampling.LANCZOS)

        # 创建 32x32 透明画布并居中
        final_img = Image.new('RGBA', (32, 32), (0, 0, 0, 0))
        paste_x = (32 - cell_img.width) // 2
        paste_y = (32 - cell_img.height) // 2
        final_img.paste(cell_img, (paste_x, paste_y), cell_img)

        # 保存
        idx = row * 7 + col
        filename = f'{cursor_names[idx]}.png'
        filepath = os.path.join(output_dir, filename)
        final_img.save(filepath)
        print(f'Saved: {filename} ({final_img.size})')

print(f'\nTotal: {len(cursor_names)} cursors saved to {output_dir}')
