const AnimationDescriptors = AnimationDescriptor[
    AnimationDescriptor(
        UUID("c4cf618f-86ca-55ba-ac0e-14f31f09940d"), nothing,
        "Scratchpad", 0, ScratchpadNode, nothing),
    AnimationDescriptor(
        UUID("4a3a9e1f-6448-554a-8e37-52f579b7476b"),
        nothing,
        "Euclid's Elements", 1, CategoryNode,
        "elements/elements_overview.jl"),
    AnimationDescriptor(
        UUID("72ebfc14-4165-584b-a571-9e9a0c86d9aa"),
        UUID("4a3a9e1f-6448-554a-8e37-52f579b7476b"),
        "Book I", 0, CategoryNode,
        "elements/book1/book_1_overview.jl"),
    AnimationDescriptor(
        UUID("17ec8ed8-e961-51fc-8025-4bb16ad8a10b"),
        UUID("72ebfc14-4165-584b-a571-9e9a0c86d9aa"),
        "Definitions", 0, CategoryNode,
        "elements/book1/book_1_definitions.jl"),
    AnimationDescriptor(
        UUID("03bf688d-40d0-56a2-a6be-ca2656c9b10d"),
        UUID("17ec8ed8-e961-51fc-8025-4bb16ad8a10b"),
        "Point", 0, LeafNode,
        "elements/book1/def_001_point.jl"),
    AnimationDescriptor(
        UUID("168548ed-ed4a-5d8b-8ac6-fb573f5637cd"),
        UUID("17ec8ed8-e961-51fc-8025-4bb16ad8a10b"),
        "Line", 1, LeafNode,
        "elements/book1/def_002_line.jl"),
    AnimationDescriptor(
        UUID("af1e6606-e27e-5dce-b21b-0e7d70a7b599"),
        UUID("17ec8ed8-e961-51fc-8025-4bb16ad8a10b"),
        "Line Extremities", 2, LeafNode,
        "elements/book1/def_003_linextrem.jl"),
    AnimationDescriptor(
        UUID("af5bd852-c740-5588-9d62-a32231cbb7cc"),
        UUID("17ec8ed8-e961-51fc-8025-4bb16ad8a10b"),
        "Straight Line", 3, LeafNode,
        "elements/book1/def_004_straightline.jl"),
    AnimationDescriptor(
        UUID("cb5384f1-0df8-5d46-8e0a-e34e1764da8c"),
        UUID("17ec8ed8-e961-51fc-8025-4bb16ad8a10b"),
        "Surface", 4, LeafNode,
        "elements/book1/def_005_surface.jl"),
    AnimationDescriptor(
        UUID("b2f240b3-12c1-5908-a7fb-4a0315929980"),
        UUID("17ec8ed8-e961-51fc-8025-4bb16ad8a10b"),
        "Surface Extremities", 5, LeafNode,
        "elements/book1/def_006_surfextrem.jl"),
    AnimationDescriptor(
        UUID("85e57539-b729-51e2-a114-441ff1c52858"),
        UUID("17ec8ed8-e961-51fc-8025-4bb16ad8a10b"),
        "Plane Surface", 6, LeafNode,
        "elements/book1/def_007_planesurface.jl"),
    AnimationDescriptor(
        UUID("18a9886f-a127-549d-8863-6deb86858661"),
        UUID("17ec8ed8-e961-51fc-8025-4bb16ad8a10b"),
        "Plane Angle", 7, LeafNode,
        "elements/book1/def_008_angle.jl"),
    AnimationDescriptor(
        UUID("144e86ef-79d1-53b5-90bd-920dc9764972"),
        UUID("17ec8ed8-e961-51fc-8025-4bb16ad8a10b"),
        "Right Angles and Perpendicular", 8, LeafNode,
        "elements/book1/def_010_perpendicular.jl"),
    AnimationDescriptor(
        UUID("142a4b16-0a1f-58f5-8599-823b8d3d2821"),
        UUID("17ec8ed8-e961-51fc-8025-4bb16ad8a10b"),
        "Obtuse Angle", 9, LeafNode,
        "elements/book1/def_011_obtuseangle.jl"),
    AnimationDescriptor(
        UUID("b81effbd-c026-5b03-895c-7a74c17f461f"),
        UUID("17ec8ed8-e961-51fc-8025-4bb16ad8a10b"),
        "Acute Angle", 10, LeafNode,
        "elements/book1/def_012_acuteangle.jl"),
    AnimationDescriptor(
        UUID("367d7638-0caa-5df0-a433-bbd4d9a7101e"),
        UUID("17ec8ed8-e961-51fc-8025-4bb16ad8a10b"),
        "Boundary", 11, LeafNode,
        "elements/book1/def_013_boundary.jl"),
    AnimationDescriptor(
        UUID("cc73ce96-0e8a-576c-9b2e-daa3b559c9ff"),
        UUID("17ec8ed8-e961-51fc-8025-4bb16ad8a10b"),
        "Figure", 12, LeafNode,
        "elements/book1/def_014_figure.jl"),
    AnimationDescriptor(
        UUID("0411aaf3-82be-5227-a146-1de5c928107d"),
        UUID("17ec8ed8-e961-51fc-8025-4bb16ad8a10b"),
        "Circle", 13, LeafNode,
        "elements/book1/def_015_circle.jl"),
    AnimationDescriptor(
        UUID("b2472007-9bab-592b-a891-8b9c97d86539"),
        UUID("17ec8ed8-e961-51fc-8025-4bb16ad8a10b"),
        "Diameter", 14, LeafNode,
        "elements/book1/def_017_diameter.jl"),
    AnimationDescriptor(
        UUID("bbe7a537-0e0c-5bd4-8855-c57883720fc9"),
        UUID("17ec8ed8-e961-51fc-8025-4bb16ad8a10b"),
        "Semicircle", 15, LeafNode,
        "elements/book1/def_018_semicircle.jl"),
    AnimationDescriptor(
        UUID("a56695b7-1b80-5582-b92b-e66fe67c0997"),
        UUID("17ec8ed8-e961-51fc-8025-4bb16ad8a10b"),
        "Trilateral Rectilineal Figures", 16, LeafNode,
        "elements/book1/def_019a_trilateral.jl"),
    AnimationDescriptor(
        UUID("61764dd7-578b-530f-ab27-052d3cc85689"),
        UUID("17ec8ed8-e961-51fc-8025-4bb16ad8a10b"),
        "Quadrilateral Rectilineal Figures", 17, LeafNode,
        "elements/book1/def_019b_quadrilateral.jl"),
    AnimationDescriptor(
        UUID("157804cd-7a32-525d-90bd-88d2f76d4f03"),
        UUID("17ec8ed8-e961-51fc-8025-4bb16ad8a10b"),
        "Multilateral Rectilineal Figures", 18, LeafNode,
        "elements/book1/def_019c_multilateral.jl"),
    AnimationDescriptor(
        UUID("b34606f5-75ed-5a20-b2f4-12d577276597"),
        UUID("17ec8ed8-e961-51fc-8025-4bb16ad8a10b"),
        "Equaliteral Triangle", 19, LeafNode,
        "elements/book1/def_020a_equilateral.jl"),
    AnimationDescriptor(
        UUID("a2a8bc49-a232-52db-baa2-cdc0fa377ae8"),
        UUID("17ec8ed8-e961-51fc-8025-4bb16ad8a10b"),
        "Isosceles Triangle", 20, LeafNode,
        "elements/book1/def_020b_isosceles.jl"),
    AnimationDescriptor(
        UUID("d270543c-19ce-5ad5-aa46-ca7570e56d4e"),
        UUID("17ec8ed8-e961-51fc-8025-4bb16ad8a10b"),
        "Scalene Triangle", 21, LeafNode,
        "elements/book1/def_020c_scalene.jl"),
    AnimationDescriptor(
        UUID("1a456c80-c785-5039-9d21-3c51bac620bf"),
        UUID("17ec8ed8-e961-51fc-8025-4bb16ad8a10b"),
        "Right-Angled Triangle", 22, LeafNode,
        "elements/book1/def_021a_righttriangle.jl"),
    AnimationDescriptor(
        UUID("86a96b17-4fe9-5b6c-bda9-5cb81f480d06"),
        UUID("17ec8ed8-e961-51fc-8025-4bb16ad8a10b"),
        "Obtuse-Angled Triangle", 23, LeafNode,
        "elements/book1/def_021b_obtusetriangle.jl"),
    AnimationDescriptor(
        UUID("fc2794f8-dbac-52a1-89e6-865e76d23cf4"),
        UUID("17ec8ed8-e961-51fc-8025-4bb16ad8a10b"),
        "Acute-Angled Triangle", 24, LeafNode,
        "elements/book1/def_021c_acutetriangle.jl"),
    AnimationDescriptor(
        UUID("9005a1bc-86a7-59b4-9dae-2f7f0f626934"),
        UUID("17ec8ed8-e961-51fc-8025-4bb16ad8a10b"),
        "Square", 25, LeafNode,
        "elements/book1/def_022a_square.jl"),
    AnimationDescriptor(
        UUID("59de9e0c-32e7-569c-aa1d-68b6f7a17067"),
        UUID("17ec8ed8-e961-51fc-8025-4bb16ad8a10b"),
        "Oblong", 26, LeafNode,
        "elements/book1/def_022b_oblong.jl"),
    AnimationDescriptor(
        UUID("eb166e05-2da3-5598-8674-f4a4ee41253f"),
        UUID("17ec8ed8-e961-51fc-8025-4bb16ad8a10b"),
        "Rhombus", 27, LeafNode,
        "elements/book1/def_022c_rhombus.jl"),
    AnimationDescriptor(
        UUID("f82efede-34ea-5ffe-8f34-ab6ae17f1860"),
        UUID("17ec8ed8-e961-51fc-8025-4bb16ad8a10b"),
        "Rhomboid", 28, LeafNode,
        "elements/book1/def_022d_rhomboid.jl"),
    AnimationDescriptor(
        UUID("4b1c5b61-6f42-55f6-ab98-00a9d84ab36c"),
        UUID("17ec8ed8-e961-51fc-8025-4bb16ad8a10b"),
        "Trapezia", 29, LeafNode,
        "elements/book1/def_022d_trapezia.jl"),
    AnimationDescriptor(
        UUID("51608ec9-487a-53f9-ba14-72c1f1750756"),
        UUID("17ec8ed8-e961-51fc-8025-4bb16ad8a10b"),
        "Parallel Straight Lines", 30, LeafNode,
        "elements/book1/def_023_parallel.jl"),
    AnimationDescriptor(
        UUID("3ca25560-30d0-5108-af69-fe99b12a2de2"),
        UUID("72ebfc14-4165-584b-a571-9e9a0c86d9aa"),
        "Postulates", 1, CategoryNode,
        "elements/book1/book_1_postulates.jl"),
    AnimationDescriptor(
        UUID("8166f691-aeae-5bfa-9828-487c7b38a4cd"),
        UUID("3ca25560-30d0-5108-af69-fe99b12a2de2"),
        "Draw a Line", 0, LeafNode,
        "elements/book1/post_01_drawline.jl"),
    AnimationDescriptor(
        UUID("4adc0a75-2177-5962-8a22-f3b7dfacc1de"),
        UUID("3ca25560-30d0-5108-af69-fe99b12a2de2"),
        "Produce a Finite Line", 1, LeafNode,
        "elements/book1/post_02_finiteline.jl"),
    AnimationDescriptor(
        UUID("4d9de8df-9439-523a-957e-99439f5ad927"),
        UUID("3ca25560-30d0-5108-af69-fe99b12a2de2"),
        "Draw a Circle", 2, LeafNode,
        "elements/book1/post_03_drawcircle.jl"),
    AnimationDescriptor(
        UUID("7f6f36f4-a711-59c8-b22d-76f7157b29df"),
        UUID("3ca25560-30d0-5108-af69-fe99b12a2de2"),
        "Equal Right Angles", 3, LeafNode,
        "elements/book1/post_04_equalright.jl"),
    AnimationDescriptor(
        UUID("4d98d3cf-e73a-5e6e-9e1d-6fa1141934e6"),
        UUID("3ca25560-30d0-5108-af69-fe99b12a2de2"),
        "Non-Parallel Lines", 4, LeafNode,
        "elements/book1/post_05_nonparallel.jl"),
    AnimationDescriptor(
        UUID("ff723537-4f80-528f-a762-39fdc8a5034a"),
        UUID("72ebfc14-4165-584b-a571-9e9a0c86d9aa"),
        "Common Notions", 2, LeafNode,
        "elements/book1/commonnotions.jl"),
    AnimationDescriptor(
        UUID("de5ce6e0-f5b2-5833-bea0-1d77adcf51ec"),
        UUID("72ebfc14-4165-584b-a571-9e9a0c86d9aa"),
        "Propositions", 3, CategoryNode,
        "elements/book1/book_1_propositions.jl"),
    AnimationDescriptor(
        UUID("76fdebfe-2600-551e-be64-03f1942f4f49"),
        UUID("de5ce6e0-f5b2-5833-bea0-1d77adcf51ec"),
        "Proposition I", 0, LeafNode,
        "elements/book1/prop_01.jl"),
    AnimationDescriptor(
        UUID("81464bfd-ae0f-5763-8617-c3846f692c33"),
        UUID("de5ce6e0-f5b2-5833-bea0-1d77adcf51ec"),
        "Proposition II", 1, LeafNode,
        "elements/book1/prop_02.jl"),
    AnimationDescriptor(
        UUID("1c6b94cb-0ecb-5f34-8ea5-30833bcc77fb"),
        nothing,
        "Proclus's Commentary", 2, CategoryNode,
        "proclus/proclus_overview.jl"),
    AnimationDescriptor(
        UUID("be7c1717-34d5-5dc9-906d-80c679269484"),
        UUID("1c6b94cb-0ecb-5f34-8ea5-30833bcc77fb"),
        "Isosceles Triangle", 0, LeafNode,
        "proclus/proclus_01_isosceles.jl"),
    AnimationDescriptor(
        UUID("fc8d5e5e-3135-53aa-8e4e-4021f78443d4"),
        UUID("1c6b94cb-0ecb-5f34-8ea5-30833bcc77fb"),
        "Scalene Triangle", 1, LeafNode,
        "proclus/proclus_02_scalene.jl"),
    AnimationDescriptor(
        UUID("65a8489e-e0bd-535f-bf47-3c5e9c9d70e6"),
        nothing,
        "Hilbert's Foundations of Geometry", 3, CategoryNode,
        "hilbert/hilbert_overview.jl"),
    AnimationDescriptor(
        UUID("df6fe312-a86c-5489-96b5-39729053df0d"),
        UUID("65a8489e-e0bd-535f-bf47-3c5e9c9d70e6"),
        "1. The Five Groups of Axioms, §1", 0, CategoryNode,
        "hilbert/1.fivegroupsaxioms/chapter_one_overview.jl"),
    AnimationDescriptor(
        UUID("d58eb2e5-ea05-5a32-9159-616484b0cc42"),
        UUID("df6fe312-a86c-5489-96b5-39729053df0d"),
        "§2 Group I: Axioms of Connection", 0, CategoryNode,
        "hilbert/1.fivegroupsaxioms/chapter_one_connection.jl"),
    AnimationDescriptor(
        UUID("027b009c-9d9c-5623-9ea0-3d462f3d1762"),
        UUID("d58eb2e5-ea05-5a32-9159-616484b0cc42"),
        "Axiom I,1", 0, LeafNode,
        "hilbert/1.fivegroupsaxioms/axiom_I1.jl"),
    AnimationDescriptor(
        UUID("4beaf2aa-0443-5607-b6e6-9147e3def7a7"),
        UUID("d58eb2e5-ea05-5a32-9159-616484b0cc42"),
        "Axiom I,2", 1, LeafNode,
        "hilbert/1.fivegroupsaxioms/axiom_I2.jl"),
    AnimationDescriptor(
        UUID("581376b6-40f3-5a65-81f0-6c6e23800851"),
        UUID("d58eb2e5-ea05-5a32-9159-616484b0cc42"),
        "Axiom I,3", 2, LeafNode,
        "hilbert/1.fivegroupsaxioms/axiom_I3.jl"),
    AnimationDescriptor(
        UUID("f26593c1-f96f-5669-bd4e-91c69a633170"),
        UUID("d58eb2e5-ea05-5a32-9159-616484b0cc42"),
        "Axiom I,4", 3, LeafNode,
        "hilbert/1.fivegroupsaxioms/axiom_I4.jl"),
    AnimationDescriptor(
        UUID("167f29ed-b6ab-5625-a965-7149688ca577"),
        UUID("d58eb2e5-ea05-5a32-9159-616484b0cc42"),
        "Axiom I,5", 4, LeafNode,
        "hilbert/1.fivegroupsaxioms/axiom_I5.jl"),
    AnimationDescriptor(
        UUID("1f2bf9eb-8f3e-5676-b3fc-f369111b509a"),
        UUID("d58eb2e5-ea05-5a32-9159-616484b0cc42"),
        "Axiom I,6", 5, LeafNode,
        "hilbert/1.fivegroupsaxioms/axiom_I6.jl"),
    AnimationDescriptor(
        UUID("8c128636-9d9f-508f-9243-4ddbeb93eead"),
        UUID("d58eb2e5-ea05-5a32-9159-616484b0cc42"),
        "Axiom I,7", 6, LeafNode,
        "hilbert/1.fivegroupsaxioms/axiom_I7.jl"),
    AnimationDescriptor(
        UUID("f465bf4b-b6c7-50e8-ab9d-8e699f415dfa"),
        UUID("d58eb2e5-ea05-5a32-9159-616484b0cc42"),
        "Theorem 1", 7, LeafNode,
        "hilbert/1.fivegroupsaxioms/theorem_1.jl"),
    AnimationDescriptor(
        UUID("ce75fdec-5412-5be8-a15e-a638bdab2c41"),
        UUID("d58eb2e5-ea05-5a32-9159-616484b0cc42"),
        "Theorem 2", 8, LeafNode,
        "hilbert/1.fivegroupsaxioms/theorem_2.jl"),
    AnimationDescriptor(
        UUID("ccb3afdf-4679-5dc7-9815-a7c3263d01b1"),
        UUID("df6fe312-a86c-5489-96b5-39729053df0d"),
        "§3 Group II: Axioms of Order", 1, CategoryNode,
        "hilbert/1.fivegroupsaxioms/chapter_one_order.jl"),
    AnimationDescriptor(
        UUID("ce2827b0-698f-5470-8e4b-cfe354bf9279"),
        UUID("ccb3afdf-4679-5dc7-9815-a7c3263d01b1"),
        "Axiom II,1", 0, LeafNode,
        "hilbert/1.fivegroupsaxioms/axiom_II1.jl"),
    AnimationDescriptor(
        UUID("9fd5d1e9-dcbb-530b-a99d-8b891f8e0746"),
        UUID("ccb3afdf-4679-5dc7-9815-a7c3263d01b1"),
        "Axiom II,2", 1, LeafNode,
        "hilbert/1.fivegroupsaxioms/axiom_II2.jl"),
    AnimationDescriptor(
        UUID("d03bba3f-b860-567f-b302-e224c23d8e4b"),
        UUID("ccb3afdf-4679-5dc7-9815-a7c3263d01b1"),
        "Axiom II,3", 2, LeafNode,
        "hilbert/1.fivegroupsaxioms/axiom_II3.jl"),
    AnimationDescriptor(
        UUID("eb7dc7d9-c9a0-5739-9b23-bcf3fc8c4ff3"),
        UUID("ccb3afdf-4679-5dc7-9815-a7c3263d01b1"),
        "Axiom II,4", 3, LeafNode,
        "hilbert/1.fivegroupsaxioms/axiom_II4.jl"),
    AnimationDescriptor(
        UUID("d60c3564-9f25-5e01-8f60-0b63dd870c05"),
        UUID("ccb3afdf-4679-5dc7-9815-a7c3263d01b1"),
        "Definition: Segments", 4, LeafNode,
        "hilbert/1.fivegroupsaxioms/def_segments.jl"),
    AnimationDescriptor(
        UUID("df459efe-fb15-5bde-898c-abf676cfa170"),
        UUID("ccb3afdf-4679-5dc7-9815-a7c3263d01b1"),
        "Axiom II,5", 5, LeafNode,
        "hilbert/1.fivegroupsaxioms/axiom_II5.jl"),
    AnimationDescriptor(
        UUID("2ee7be59-eea9-5903-b552-d3f0c18084ac"),
        UUID("df6fe312-a86c-5489-96b5-39729053df0d"),
        "§4 Consequences after Group II", 2, CategoryNode,
        "hilbert/1.fivegroupsaxioms/chapter_one_consequences.jl"),
    AnimationDescriptor(
        UUID("d119466f-cf6b-569a-8228-f5e21b753b74"),
        UUID("2ee7be59-eea9-5903-b552-d3f0c18084ac"),
        "Theorem 3", 0, LeafNode,
        "hilbert/1.fivegroupsaxioms/theorem_3.jl"),
    AnimationDescriptor(
        UUID("9cae95dd-c90e-5425-8acf-ba7dc6823c48"),
        UUID("2ee7be59-eea9-5903-b552-d3f0c18084ac"),
        "Theorem 4", 1, LeafNode,
        "hilbert/1.fivegroupsaxioms/theorem_4.jl"),
    AnimationDescriptor(
        UUID("bd35d685-60be-5b15-bd2e-48d59ff1e75b"),
        UUID("2ee7be59-eea9-5903-b552-d3f0c18084ac"),
        "Theorem 5", 2, LeafNode,
        "hilbert/1.fivegroupsaxioms/theorem_5.jl"),
    AnimationDescriptor(
        UUID("40c5fc2c-8686-56b7-9840-838f6f4c8147"),
        UUID("2ee7be59-eea9-5903-b552-d3f0c18084ac"),
        "Definition: Half-rays", 3, LeafNode,
        "hilbert/1.fivegroupsaxioms/def_halfrays.jl"),
    AnimationDescriptor(
        UUID("fdc6cded-a63f-5b19-ad63-8876317366ce"),
        UUID("2ee7be59-eea9-5903-b552-d3f0c18084ac"),
        "Definition: Side of Line", 4, LeafNode,
        "hilbert/1.fivegroupsaxioms/def_sideofline.jl"),
    AnimationDescriptor(
        UUID("1c3ab917-1634-54b1-a83d-e91cf39dd290"),
        UUID("2ee7be59-eea9-5903-b552-d3f0c18084ac"),
        "Definition: Polygon", 5, LeafNode,
        "hilbert/1.fivegroupsaxioms/def_polygon.jl"),
    AnimationDescriptor(
        UUID("88d5a96a-0b6e-5833-9fb6-25b7f0ff4b7b"),
        UUID("2ee7be59-eea9-5903-b552-d3f0c18084ac"),
        "Theorem 6", 6, LeafNode,
        "hilbert/1.fivegroupsaxioms/theorem_6.jl"),
    AnimationDescriptor(
        UUID("e5338e25-924a-52dc-b074-e5a8cc3b234b"),
        UUID("2ee7be59-eea9-5903-b552-d3f0c18084ac"),
        "Theorem 7", 7, LeafNode,
        "hilbert/1.fivegroupsaxioms/theorem_7.jl"),
    AnimationDescriptor(
        UUID("4403bc1b-8656-5b06-a536-ba2e58afab84"),
        UUID("df6fe312-a86c-5489-96b5-39729053df0d"),
        "§5 Group III: Axiom of Parallels", 3, CategoryNode,
        "hilbert/1.fivegroupsaxioms/chapter_one_parallels.jl"),
    AnimationDescriptor(
        UUID("6fe08874-492a-50e6-a69c-b993b39369d0"),
        UUID("4403bc1b-8656-5b06-a536-ba2e58afab84"),
        "Axiom III", 0, LeafNode,
        "hilbert/1.fivegroupsaxioms/axiom_III1.jl"),
    AnimationDescriptor(
        UUID("24ae243e-b98c-5a4d-8a41-99d6a29e5fa4"),
        UUID("4403bc1b-8656-5b06-a536-ba2e58afab84"),
        "Theorem 8", 1, LeafNode,
        "hilbert/1.fivegroupsaxioms/theorem_8.jl"),
    AnimationDescriptor(
        UUID("00649289-1cde-5d72-b45a-08f7b28662ca"),
        UUID("df6fe312-a86c-5489-96b5-39729053df0d"),
        "§6 Group IV: Axioms of Congruence", 4, CategoryNode,
        "hilbert/1.fivegroupsaxioms/chapter_one_congruence.jl"),
    AnimationDescriptor(
        UUID("de476bfb-05e5-58bb-a07b-b3fdfe8bf42d"),
        UUID("00649289-1cde-5d72-b45a-08f7b28662ca"),
        "Axiom IV,1", 0, LeafNode,
        "hilbert/1.fivegroupsaxioms/axiom_IV1.jl"),
    AnimationDescriptor(
        UUID("bda3b319-b9c8-5a9f-bd21-c778c2f66b1e"),
        UUID("00649289-1cde-5d72-b45a-08f7b28662ca"),
        "Axiom IV,2", 1, LeafNode,
        "hilbert/1.fivegroupsaxioms/axiom_IV2.jl"),
    AnimationDescriptor(
        UUID("cb213191-4c0f-5a1d-8104-eb651e1123db"),
        UUID("00649289-1cde-5d72-b45a-08f7b28662ca"),
        "Axiom IV,3", 2, LeafNode,
        "hilbert/1.fivegroupsaxioms/axiom_IV3.jl"),
    AnimationDescriptor(
        UUID("046525bc-cbdb-5b6b-96c4-49dd105e9b9e"),
        UUID("00649289-1cde-5d72-b45a-08f7b28662ca"),
        "Definition: Angle", 3, LeafNode,
        "hilbert/1.fivegroupsaxioms/def_angle.jl"),
    AnimationDescriptor(
        UUID("de9f30ff-7cd4-5eaa-bfe4-ecd5c1c4de9a"),
        UUID("00649289-1cde-5d72-b45a-08f7b28662ca"),
        "Axiom IV,4", 4, LeafNode,
        "hilbert/1.fivegroupsaxioms/axiom_IV4.jl"),
    AnimationDescriptor(
        UUID("1e893976-4bb4-573a-bc2d-b097eb312f98"),
        UUID("00649289-1cde-5d72-b45a-08f7b28662ca"),
        "Axiom IV,5", 5, LeafNode,
        "hilbert/1.fivegroupsaxioms/axiom_IV5.jl"),
    AnimationDescriptor(
        UUID("93310d74-5fee-5cae-b308-1e8da917a619"),
        UUID("00649289-1cde-5d72-b45a-08f7b28662ca"),
        "Definition: Triangle Angle", 6, LeafNode,
        "hilbert/1.fivegroupsaxioms/def_triangle_angle.jl"),
    AnimationDescriptor(
        UUID("38d8b49f-063a-5365-9d3d-f05d967064f1"),
        UUID("00649289-1cde-5d72-b45a-08f7b28662ca"),
        "Axiom IV,6", 7, LeafNode,
        "hilbert/1.fivegroupsaxioms/axiom_IV6.jl"),
    AnimationDescriptor(
        UUID("c80d3bfc-88be-5b70-af19-c7edcc240c23"),
        UUID("df6fe312-a86c-5489-96b5-39729053df0d"),
        "§7 Consequences after Group IV", 5, CategoryNode,
        "hilbert/1.fivegroupsaxioms/chapter_one_congruence_consequences.jl"),
    AnimationDescriptor(
        UUID("2d7e1d1c-6c4d-5a1b-bb8e-dc7d30c84e51"),
        UUID("c80d3bfc-88be-5b70-af19-c7edcc240c23"),
        "Theorem 9", 0, LeafNode,
        "hilbert/1.fivegroupsaxioms/theorem_9.jl"),
    AnimationDescriptor(
        UUID("5a6f6d8c-cce6-59ef-ad49-b9ad19177f23"),
        UUID("c80d3bfc-88be-5b70-af19-c7edcc240c23"),
        "Definition: Congruent Angles", 1, LeafNode,
        "hilbert/1.fivegroupsaxioms/def_congruent_angles.jl"),
    AnimationDescriptor(
        UUID("b3709506-caed-5801-8ebf-29ff50c1f6ef"),
        UUID("c80d3bfc-88be-5b70-af19-c7edcc240c23"),
        "Definition: Supplementary Angles", 2, LeafNode,
        "hilbert/1.fivegroupsaxioms/def_supplementary_angles.jl"),
    AnimationDescriptor(
        UUID("f22779f8-3c27-592f-b9d8-6f6768bdc8f5"),
        UUID("c80d3bfc-88be-5b70-af19-c7edcc240c23"),
        "Definition: Congruent Triangles", 3, LeafNode,
        "hilbert/1.fivegroupsaxioms/def_congruent_triangles.jl"),
    AnimationDescriptor(
        UUID("0b80bb83-049d-5385-a481-326c27126f49"),
        UUID("c80d3bfc-88be-5b70-af19-c7edcc240c23"),
        "Theorem 10", 4, LeafNode,
        "hilbert/1.fivegroupsaxioms/theorem_10.jl"),
    AnimationDescriptor(
        UUID("d4158f1e-0115-5115-9dab-9a75895c1af1"),
        UUID("c80d3bfc-88be-5b70-af19-c7edcc240c23"),
        "Theorem 11", 5, LeafNode,
        "hilbert/1.fivegroupsaxioms/theorem_11.jl"),
    AnimationDescriptor(
        UUID("94255381-8250-5e52-8b42-df5d5fb68af6"),
        UUID("c80d3bfc-88be-5b70-af19-c7edcc240c23"),
        "Theorem 12", 6, LeafNode,
        "hilbert/1.fivegroupsaxioms/theorem_12.jl"),
    AnimationDescriptor(
        UUID("a156d843-ed14-5a5e-b311-7cf82957295c"),
        UUID("c80d3bfc-88be-5b70-af19-c7edcc240c23"),
        "Theorem 13", 7, LeafNode,
        "hilbert/1.fivegroupsaxioms/theorem_13.jl"),
    AnimationDescriptor(
        UUID("697be89f-daea-5bae-b872-8286faf44b34"),
        UUID("c80d3bfc-88be-5b70-af19-c7edcc240c23"),
        "Theorem 14", 8, LeafNode,
        "hilbert/1.fivegroupsaxioms/theorem_14.jl"),
    AnimationDescriptor(
        UUID("968ab5d1-72e6-50d8-aea3-02775f05c29d"),
        UUID("c80d3bfc-88be-5b70-af19-c7edcc240c23"),
        "Theorem 15", 9, LeafNode,
        "hilbert/1.fivegroupsaxioms/theorem_15.jl"),
    AnimationDescriptor(
        UUID("ad0416c5-2429-5ae3-8143-2594a6aca758"),
        UUID("c80d3bfc-88be-5b70-af19-c7edcc240c23"),
        "Theorem 16", 10, LeafNode,
        "hilbert/1.fivegroupsaxioms/theorem_16.jl"),
    AnimationDescriptor(
        UUID("71d6cce5-385d-57d5-bbcd-209393b3ca15"),
        UUID("c80d3bfc-88be-5b70-af19-c7edcc240c23"),
        "Definition: Figure", 11, LeafNode,
        "hilbert/1.fivegroupsaxioms/def_figure.jl"),
    AnimationDescriptor(
        UUID("43ffb287-fbcf-5a9e-87dc-48221544d19d"),
        UUID("c80d3bfc-88be-5b70-af19-c7edcc240c23"),
        "Theorem 17", 12, LeafNode,
        "hilbert/1.fivegroupsaxioms/theorem_17.jl"),
    AnimationDescriptor(
        UUID("db80657d-3c76-554e-9bec-b193cc6dcdbf"),
        UUID("c80d3bfc-88be-5b70-af19-c7edcc240c23"),
        "Theorem 18", 13, LeafNode,
        "hilbert/1.fivegroupsaxioms/theorem_18.jl"),
    AnimationDescriptor(
        UUID("83d5f06e-a942-5ce2-ab02-8497772f5b4c"),
        UUID("c80d3bfc-88be-5b70-af19-c7edcc240c23"),
        "Theorem 19", 14, LeafNode,
        "hilbert/1.fivegroupsaxioms/theorem_19.jl"),
    AnimationDescriptor(
        UUID("f093e4fb-8651-5385-8837-60c25cccebc3"),
        UUID("c80d3bfc-88be-5b70-af19-c7edcc240c23"),
        "Theorem 20", 15, LeafNode,
        "hilbert/1.fivegroupsaxioms/theorem_20.jl"),
    AnimationDescriptor(
        UUID("de38d73f-9331-5fea-91c2-7c53b135bdc7"),
        UUID("c80d3bfc-88be-5b70-af19-c7edcc240c23"),
        "Definition: Circle", 16, LeafNode,
        "hilbert/1.fivegroupsaxioms/def_circle.jl"),
    AnimationDescriptor(
        UUID("2e0a8725-94ef-5c51-93df-f35356806483"),
        UUID("df6fe312-a86c-5489-96b5-39729053df0d"),
        "§8 Group V: Axiom of Continuity", 6, CategoryNode,
        "hilbert/1.fivegroupsaxioms/chapter_one_continuity.jl"),
    AnimationDescriptor(
        UUID("61db4469-083e-5c1e-b646-5b90b038f8b7"),
        UUID("2e0a8725-94ef-5c51-93df-f35356806483"),
        "Axiom V", 0, LeafNode,
        "hilbert/1.fivegroupsaxioms/axiom_V.jl"),
    AnimationDescriptor(
        UUID("b47188c2-2829-5320-82c1-caf2666314b2"),
        UUID("2e0a8725-94ef-5c51-93df-f35356806483"),
        "Axiom of Completeness", 1, LeafNode,
        "hilbert/1.fivegroupsaxioms/axiom_completeness.jl"),
    AnimationDescriptor(
        UUID("a8bd259b-0c7b-5b60-b21f-84095e2eb903"),
        nothing,
        "Algebra", 4, CategoryNode,
        "algebra/algebra_overview.jl"),
    AnimationDescriptor(
        UUID("1c54c525-f85a-55a9-931b-8cfaafabec03"),
        UUID("a8bd259b-0c7b-5b60-b21f-84095e2eb903"),
        "Groups", 0, CategoryNode,
        "algebra/groups/groups_overview.jl"),
    AnimationDescriptor(
        UUID("de580f25-1901-50de-84b3-3d7966a8bfd4"),
        UUID("1c54c525-f85a-55a9-931b-8cfaafabec03"),
        "ℤ₂", 0, CategoryNode,
        "algebra/groups/z_2.jl"),
    AnimationDescriptor(
        UUID("7224b6e5-b665-541d-9cc6-dc09c4cc380f"),
        UUID("de580f25-1901-50de-84b3-3d7966a8bfd4"),
        "Closure", 0, LeafNode,
        "algebra/groups/z_2_closure.jl"),
    AnimationDescriptor(
        UUID("a61d43d4-4aee-5c07-8122-276807bc7dfa"),
        UUID("de580f25-1901-50de-84b3-3d7966a8bfd4"),
        "Identity", 1, LeafNode,
        "algebra/groups/z_2_identity.jl"),
    AnimationDescriptor(
        UUID("b8a7ebd1-d89b-597c-aa7a-761008dc0113"),
        UUID("de580f25-1901-50de-84b3-3d7966a8bfd4"),
        "Inverse", 2, LeafNode,
        "algebra/groups/z_2_inverse.jl"),
    AnimationDescriptor(
        UUID("36baf769-897f-5e3d-8e7f-a5f7dd605dd7"),
        UUID("1c54c525-f85a-55a9-931b-8cfaafabec03"),
        "Cₙ", 1, CategoryNode,
        "algebra/groups/C_n.jl"),
    AnimationDescriptor(
        UUID("179367e3-1b5d-5ffe-923b-d9daf783d9d4"),
        UUID("36baf769-897f-5e3d-8e7f-a5f7dd605dd7"),
        "Associative", 0, LeafNode,
        "algebra/groups/C_n_associative.jl"),
    AnimationDescriptor(
        UUID("ab55384b-ed8e-5a51-b367-4ea2b4fbd9fb"),
        UUID("36baf769-897f-5e3d-8e7f-a5f7dd605dd7"),
        "Abelian", 1, LeafNode,
        "algebra/groups/C_n_abelian.jl"),
]
